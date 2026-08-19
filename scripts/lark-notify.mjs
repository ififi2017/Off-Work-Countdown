#!/usr/bin/env node

/**
 * 往飞书 / Lark 自定义机器人推送通知。
 *
 * 只用自定义机器人，不用企业自建应用：这四类通知都是单向推送到一个群，
 * 机器人够用（限流 100 次/分、5 次/秒，发版最多几条）。自建应用才需要的是多群、
 * 收指令和**上传文件**——安装包这里发链接，不传文件。
 *
 * ⚠️ webhook URL 等同于密钥，只从环境变量读，永远不要写进仓库。务必在飞书那边
 * 开启签名校验：开了之后光有 URL 也发不出消息。
 */

import { createHmac } from "node:crypto";

/**
 * 飞书的签名算法有个很反直觉的地方：HMAC 的 **key** 是 `timestamp\nsecret`，
 * 而**消息体是空字符串**——不是对 payload 签名。写成对 payload 签名只会一直收到
 * 鉴权失败。此实现与官方文档的 Python 参考实现做过逐字节交叉验证。
 */
export function larkSign(timestampSeconds, secret) {
  return createHmac("sha256", `${timestampSeconds}\n${secret}`)
    .update("")
    .digest("base64");
}

const COLORS = {
  success: "green",
  failure: "red",
  info: "blue",
  release: "carmine",
};

function link(text, url) {
  return url ? `[${text}](${url})` : text;
}

/**
 * 把一次事件渲染成飞书消息卡片。
 *
 * 纯函数，不碰网络，卡片 JSON 很容易写错且往往只有线上才发现，所以单独抽出来做单测。
 */
export function buildCard(kind, data = {}) {
  const repo = data.repo ?? "";
  const lines = [];
  let title;
  let color;

  switch (kind) {
    case "ci-failure":
      title = `CI 失败 · ${data.branch ?? "?"}`;
      color = COLORS.failure;
      lines.push(`**工作流**：${data.workflow ?? "?"}`);
      lines.push(`**分支**：${data.branch ?? "?"}`);
      if (data.commitMessage) lines.push(`**提交**：${data.commitMessage}`);
      lines.push(link("查看运行日志", data.runUrl));
      break;

    case "ci-recovered":
      title = `CI 恢复 · ${data.branch ?? "?"}`;
      color = COLORS.success;
      lines.push(`**工作流**：${data.workflow ?? "?"} 已恢复通过`);
      lines.push(link("查看运行", data.runUrl));
      break;

    case "release-draft":
      title = `构建完成，草稿待发布 · ${data.version ?? "?"}`;
      color = COLORS.info;
      // 草稿的资产链接需要仓库权限才能下载，所以这条只提醒去审核发布，不放下载链接。
      lines.push("安装包已构建并签名，Release 仍是**草稿**状态。");
      lines.push("确认无误后在 GitHub 上手动发布，届时会再推一条带下载链接的通知。");
      lines.push(link("打开 Release 草稿", data.releaseUrl));
      break;

    case "release-published": {
      title = `新版本发布 · ${data.version ?? "?"}`;
      color = COLORS.release;
      lines.push(link("Release 页面", data.releaseUrl));
      const assets = data.assets ?? [];
      if (assets.length > 0) {
        lines.push("");
        lines.push("**下载**");
        for (const asset of assets) {
          // 直链 + 镜像各给一条：飞书用户大多在国内，github.com 直链很慢，
          // 而项目本来就有 gh-proxy 反代基建（见 scripts/mirror-manifest.mjs）。
          const parts = [link("直链", asset.url)];
          if (asset.mirrorUrl) parts.push(link("镜像", asset.mirrorUrl));
          lines.push(`- ${asset.name}　${parts.join(" · ")}`);
        }
      }
      break;
    }

    case "issue-opened":
      title = `新 Issue · #${data.number ?? "?"}`;
      color = COLORS.info;
      lines.push(`**${data.subject ?? ""}**`);
      if (data.author) lines.push(`来自 ${data.author}`);
      lines.push(link("查看", data.url));
      break;

    case "pr-merged":
      title = `PR 已合并 · #${data.number ?? "?"}`;
      color = COLORS.success;
      lines.push(`**${data.subject ?? ""}**`);
      lines.push(link("查看", data.url));
      break;

    default:
      throw new Error(`Unknown notification kind: ${kind}`);
  }

  if (repo) {
    lines.push("");
    lines.push(`<font color="grey">${repo}</font>`);
  }

  return {
    schema: "2.0",
    header: {
      title: { tag: "plain_text", content: title },
      template: color,
    },
    body: {
      elements: [{ tag: "markdown", content: lines.join("\n") }],
    },
  };
}

/** 组装最终请求体，签名字段仅在配置了密钥时附加。 */
export function buildPayload(card, { secret, timestampSeconds } = {}) {
  const payload = { msg_type: "interactive", card };
  if (secret) {
    const timestamp = String(
      timestampSeconds ?? Math.floor(Date.now() / 1000)
    );
    payload.timestamp = timestamp;
    payload.sign = larkSign(timestamp, secret);
  }
  return payload;
}

export async function sendCard(card, { webhook, secret, fetchImpl = fetch } = {}) {
  const response = await fetchImpl(webhook, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(buildPayload(card, { secret })),
  });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new Error(`Lark returned a non-JSON response: ${text.slice(0, 200)}`);
  }
  // ⚠️ 飞书对业务错误也返回 HTTP 200，必须看 body.code，光判断 response.ok 会把
  // 签名错误、机器人被移除等情况当成发送成功。
  if (body.code !== 0) {
    throw new Error(`Lark rejected the message: code=${body.code} msg=${body.msg}`);
  }
  return body;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const kind = process.argv[2];
  const data = process.argv[3] ? JSON.parse(process.argv[3]) : {};
  const webhook = process.env.LARK_WEBHOOK;
  const secret = process.env.LARK_SIGN_SECRET;

  // fork 的 PR 拿不到 secrets，本地跑也没有——这不是错误，安静跳过即可，
  // 否则每个外部贡献者的 PR 都会看到一个红叉。
  if (!webhook) {
    console.log("LARK_WEBHOOK is not set; skipping notification.");
    process.exit(0);
  }

  try {
    await sendCard(buildCard(kind, data), { webhook, secret });
    console.log(`Sent Lark notification: ${kind}`);
  } catch (error) {
    // 退出码非 0 让日志里看得见，工作流那边用 continue-on-error 保证不影响构建。
    console.error(`Failed to send Lark notification: ${error.message}`);
    process.exit(1);
  }
}
