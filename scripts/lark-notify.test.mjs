import { describe, expect, it } from "vitest";
import {
  buildCard,
  buildPayload,
  larkSign,
  sendCard,
} from "./lark-notify.mjs";

describe("larkSign", () => {
  // 取自官方文档 Python 参考实现的输出，逐字节比对过。
  // key 是 `timestamp\nsecret`、消息体为空——写成对 payload 签名会一直鉴权失败。
  it("matches the reference implementation", () => {
    expect(larkSign("1599360473", "abc")).toBe(
      "cgtpJzI2j6bUDggbdGYjskCK3FPgKpTkwosfWsMzKqM="
    );
    expect(larkSign("1786000000", "s3cr3t-中文")).toBe(
      "TgTftn4yLa7ecBll0npecrIq7wxH5HYtHDnvM+aKOHs="
    );
  });
});

describe("buildPayload", () => {
  it("omits signature fields when no secret is configured", () => {
    const payload = buildPayload(buildCard("pr-merged", { number: 1 }));
    expect(payload.msg_type).toBe("interactive");
    expect(payload).not.toHaveProperty("sign");
    expect(payload).not.toHaveProperty("timestamp");
  });

  it("signs with a second-precision timestamp", () => {
    const payload = buildPayload(buildCard("pr-merged", { number: 1 }), {
      secret: "abc",
      timestampSeconds: 1599360473,
    });
    expect(payload.timestamp).toBe("1599360473");
    expect(payload.sign).toBe(larkSign("1599360473", "abc"));
  });
});

describe("buildCard", () => {
  const content = (card) => card.body.elements[0].content;

  it("rejects an unknown kind instead of sending an empty card", () => {
    expect(() => buildCard("nope")).toThrow(/Unknown notification kind/);
  });

  it("keeps download links out of the draft notice", () => {
    const card = buildCard("release-draft", {
      version: "3.1.6",
      releaseUrl: "https://example.com/draft",
    });
    // 草稿资产需要仓库权限才能下载，放链接等于给群里一条打不开的地址。
    // 断言的是「没有真的下载链接」，不是字面词——正文里提到"下载"是允许的。
    expect(content(card)).toContain("草稿");
    expect(content(card)).not.toContain("[直链](");
    expect(content(card)).not.toContain("[镜像](");
  });

  it("lists both the direct and mirrored download for each asset", () => {
    const card = buildCard("release-published", {
      version: "3.1.6",
      releaseUrl: "https://example.com/r",
      assets: [
        {
          name: "app_aarch64.dmg",
          url: "https://github.com/a.dmg",
          mirrorUrl: "https://gh-proxy.com/https://github.com/a.dmg",
        },
      ],
    });
    expect(content(card)).toContain("[直链](https://github.com/a.dmg)");
    expect(content(card)).toContain(
      "[镜像](https://gh-proxy.com/https://github.com/a.dmg)"
    );
  });

  it("omits the mirror link when there is no mirrored URL", () => {
    const card = buildCard("release-published", {
      assets: [{ name: "x.msi", url: "https://github.com/x.msi" }],
    });
    expect(content(card)).toContain("直链");
    expect(content(card)).not.toContain("镜像");
  });

  it("colours failure and recovery differently", () => {
    expect(buildCard("ci-failure", {}).header.template).toBe("red");
    expect(buildCard("ci-recovered", {}).header.template).toBe("green");
  });
});

describe("sendCard", () => {
  const ok = { code: 0, msg: "success" };

  it("treats a non-zero body code as a failure even on HTTP 200", async () => {
    // ⚠️ 飞书对业务错误也返回 HTTP 200。只看 response.ok 会把签名错误、机器人
    // 被移除等情况当成发送成功——那样线上出问题时毫无征兆。
    const fetchImpl = async () => ({
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ code: 19021, msg: "sign match fail" }),
    });
    await expect(
      sendCard(buildCard("pr-merged", {}), { webhook: "u", fetchImpl })
    ).rejects.toThrow(/code=19021/);
  });

  it("surfaces a non-JSON response instead of throwing a parse error", async () => {
    const fetchImpl = async () => ({
      ok: false,
      status: 502,
      text: async () => "<html>bad gateway</html>",
    });
    await expect(
      sendCard(buildCard("pr-merged", {}), { webhook: "u", fetchImpl })
    ).rejects.toThrow(/non-JSON response/);
  });

  it("posts a signed payload to the webhook", async () => {
    let seen;
    const fetchImpl = async (url, init) => {
      seen = { url, body: JSON.parse(init.body) };
      return { ok: true, status: 200, text: async () => JSON.stringify(ok) };
    };
    await sendCard(buildCard("issue-opened", { number: 7 }), {
      webhook: "https://example.com/hook",
      secret: "abc",
      fetchImpl,
    });
    expect(seen.url).toBe("https://example.com/hook");
    expect(seen.body.msg_type).toBe("interactive");
    expect(seen.body.sign).toBeTruthy();
  });
});
