import { sign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const DEFAULT_BASE_URL = "https://api.appstoreconnect.apple.com";

function base64Url(value) {
  return Buffer.from(value).toString("base64url");
}

export function createJwt({ keyId, issuerId, privateKey, nowSeconds = Math.floor(Date.now() / 1000) }) {
  if (!keyId || !issuerId || !privateKey) throw new Error("keyId, issuerId, and privateKey are required.");
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = base64Url(
    JSON.stringify({
      iss: issuerId,
      iat: nowSeconds - 30,
      exp: nowSeconds + 19 * 60,
      aud: "appstoreconnect-v1",
    })
  );
  const signingInput = `${header}.${payload}`;
  const signature = sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${signature.toString("base64url")}`;
}

export function credentialsFromEnv(env = process.env) {
  const keyId = env.ASC_KEY_ID;
  const issuerId = env.ASC_ISSUER_ID;
  const keyPath =
    env.ASC_PRIVATE_KEY_PATH ??
    (keyId ? `${env.HOME ?? ""}/.appstoreconnect/private_keys/AuthKey_${keyId}.p8` : undefined);
  const missing = [
    ["ASC_KEY_ID", keyId],
    ["ASC_ISSUER_ID", issuerId],
    ["ASC_PRIVATE_KEY_PATH", keyPath],
  ]
    .filter(([, value]) => !value)
    .map(([name]) => name);
  if (missing.length > 0) {
    throw new Error(`Missing App Store Connect credentials: ${missing.join(", ")}.`);
  }
  if (!existsSync(keyPath)) throw new Error(`ASC_PRIVATE_KEY_PATH does not exist: ${keyPath}`);
  return { keyId, issuerId, privateKey: readFileSync(keyPath, "utf8") };
}

function errorDetails(body) {
  if (!body || typeof body !== "object") return null;
  if (!Array.isArray(body.errors)) return null;
  return body.errors
    .map((error) =>
      [error.status, error.code, error.title, error.detail, error.source?.pointer]
        .filter(Boolean)
        .join(" · ")
    )
    .join("\n");
}

async function parseResponse(response) {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function requestUrl(baseUrl, pathOrUrl) {
  return pathOrUrl.startsWith("http://") || pathOrUrl.startsWith("https://")
    ? pathOrUrl
    : new URL(pathOrUrl, baseUrl).toString();
}

export function createApiClient({
  credentials,
  baseUrl = DEFAULT_BASE_URL,
  fetchImpl = fetch,
  retryCount = 3,
} = {}) {
  if (!credentials) throw new Error("App Store Connect credentials are required.");

  async function request(pathOrUrl, { method = "GET", body, headers = {} } = {}) {
    const url = requestUrl(baseUrl, pathOrUrl);
    for (let attempt = 0; ; attempt += 1) {
      const token = createJwt(credentials);
      const response = await fetchImpl(url, {
        method,
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${token}`,
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
          ...headers,
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      // A timed-out POST may already have created a resource. Retrying it can create a
      // duplicate localization or screenshot reservation, so only retry unambiguously
      // rejected rate-limited requests and idempotent methods.
      const shouldRetry = response.status === 429 || (method !== "POST" && response.status >= 500);
      if (shouldRetry && attempt < retryCount) {
        const retryAfter = Number(response.headers.get("retry-after"));
        await response.arrayBuffer();
        await delay(Number.isFinite(retryAfter) ? Math.min(retryAfter * 1000, 10_000) : 500 * 2 ** attempt);
        continue;
      }
      const parsed = await parseResponse(response);
      if (!response.ok) {
        const details = errorDetails(parsed);
        const fallback = typeof parsed === "string" ? parsed.slice(0, 500) : JSON.stringify(parsed);
        throw new Error(
          `App Store Connect ${method} ${new URL(url).pathname} failed (${response.status})${
            details || fallback ? `:\n${details ?? fallback}` : "."
          }`
        );
      }
      return parsed;
    }
  }

  async function list(pathOrUrl) {
    const items = [];
    let next = pathOrUrl;
    while (next) {
      const page = await request(next);
      items.push(...(page?.data ?? []));
      next = page?.links?.next ?? null;
    }
    return items;
  }

  async function uploadParts(operations, content) {
    for (const [index, operation] of operations.entries()) {
      const start = operation.offset ?? 0;
      const end = start + operation.length;
      const part = content.subarray(start, end);
      if (part.length !== operation.length) {
        throw new Error(
          `Apple requested ${operation.length} bytes for screenshot part ${index + 1}, but only ${part.length} are available.`
        );
      }
      const operationHeaders = Object.fromEntries(
        (operation.requestHeaders ?? []).map((header) => [header.name, header.value])
      );
      for (let attempt = 0; ; attempt += 1) {
        let response;
        try {
          response = await fetchImpl(operation.url, {
            method: operation.method,
            headers: operationHeaders,
            body: part,
          });
        } catch (error) {
          if (attempt < retryCount) {
            await delay(500 * 2 ** attempt);
            continue;
          }
          throw new Error(
            `Screenshot upload part ${index + 1}/${operations.length} failed after ${attempt + 1} attempts: ${
              error instanceof Error ? error.message : error
            }`
          );
        }
        if (response.ok) break;
        const message = (await response.text()).slice(0, 500);
        if ((response.status === 429 || response.status >= 500) && attempt < retryCount) {
          await delay(500 * 2 ** attempt);
          continue;
        }
        throw new Error(
          `Screenshot upload part ${index + 1}/${operations.length} failed (${response.status})${
            message ? `: ${message}` : "."
          }`
        );
      }
    }
  }

  return { request, list, uploadParts };
}
