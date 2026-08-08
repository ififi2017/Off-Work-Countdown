// 仅供服务端使用：这里会读取 Upstash 的访问令牌，绝不能被客户端组件引入。
// 放在 lib/server/ 下与既有约定一致（见 lib/server/i18n.ts）。
//
// Upstash Redis 的 REST 接口，直接用 fetch 调用——只需要 INCR 和批量 GET，
// 为此引入一个 SDK 不划算。
//
// 环境变量兼容两套命名：Vercel Marketplace 的 Upstash 集成注入
// UPSTASH_REDIS_REST_*，早期的 Vercel KV 注入 KV_REST_API_*。
// 两者都没有时整个模块降级为 no-op，这样本地开发、CI 和自部署的用户
// 不配任何东西也能正常构建运行。

function credentials(): { url: string; token: string } | null {
  const url =
    process.env.UPSTASH_REDIS_REST_URL ?? process.env.KV_REST_API_URL ?? "";
  const token =
    process.env.UPSTASH_REDIS_REST_TOKEN ?? process.env.KV_REST_API_TOKEN ?? "";
  if (!url || !token) return null;
  return { url: url.replace(/\/$/, ""), token };
}

export function isAnalyticsConfigured(): boolean {
  return credentials() !== null;
}

/** 事件计数按天分桶：e:2026-08-08:share_land */
export function eventKey(event: string, date = new Date()): string {
  return `e:${date.toISOString().slice(0, 10)}:${event}`;
}

export async function incrementEvent(event: string): Promise<void> {
  const creds = credentials();
  if (!creds) return;

  try {
    await fetch(`${creds.url}/incr/${encodeURIComponent(eventKey(event))}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${creds.token}` },
      cache: "no-store",
    });
  } catch {
    // 存储不可用时静默失败——埋点不该让请求出错
  }
}

/** 批量读取计数，缺失的键按 0 计。 */
export async function readCounts(
  keys: string[]
): Promise<Record<string, number>> {
  const creds = credentials();
  if (!creds || keys.length === 0) return {};

  const res = await fetch(`${creds.url}/pipeline`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${creds.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(keys.map((k) => ["GET", k])),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`upstash pipeline ${res.status}`);

  const rows = (await res.json()) as Array<{ result: string | null }>;
  return Object.fromEntries(
    keys.map((k, i) => [k, Number(rows[i]?.result ?? 0) || 0])
  );
}
