#!/usr/bin/env node

/**
 * 埋点日报 / 周报 / 月报，推送到飞书。
 *
 * 复用 lark-notify.mjs 的自定义机器人通道（签名算法那个坑已经在那边踩过并注释）。
 * 数据来自 /api/e/stats，天按北京时间切分，见 lib/server/analytics.ts。
 *
 * ⚠️ 这套埋点是刻意的**纯聚合计数**：不写 cookie、不记 IP、不带任何标识。所以
 * 报表只能给「事件发生了多少次」和事件之间的比率，给不了 UV、留存，也给不了
 * 「同一批人」的漏斗——两个事件的比值是次数比，不是人数比。措辞别写成人数。
 */

import { sendCard } from "./lark-notify.mjs";

const DEFAULT_BASE_URL = "https://off.rainif.com";

/** 报表里逐个列出的下载渠道，顺序即卡片里的展示顺序。 */
const DOWNLOAD_CHANNELS = [
  ["desktop_download_msstore", "微软商店"],
  ["desktop_download_macappstore", "Mac App Store"],
  ["desktop_download_windows_intel", "Windows x64"],
  ["desktop_download_windows_arm", "Windows ARM64"],
  ["desktop_download_macos_apple", "macOS Apple 芯片"],
  ["desktop_download_macos_intel", "macOS Intel"],
  ["desktop_download_linux_intel", "Linux"],
  ["desktop_download_github", "GitHub Releases"],
];

/** 比率都是**次数之比**，不是人数之比——分子分母来自两个独立的计数器。 */
const RATIOS = [
  {
    label: "分享落地 → 换成我的时间",
    from: "share_land",
    to: "share_convert",
  },
  {
    label: "Mac 浮窗 → 跳转 App Store",
    from: "desktop_macappstore_dialog_open",
    to: "desktop_download_macappstore",
  },
  {
    label: "下载邀请 → 进入下载页",
    from: "desktop_invite_view",
    to: "desktop_invite_open",
  },
];

const PERIODS = {
  daily: { days: 15, unit: "日报", sparkLabel: "最近 14 天", sparkMax: 14 },
  // 周报和月报都拉满 90 天：/api/e/stats 的上限就是 90，而完整周／完整月要靠
  // 窗口内的天数凑齐，宁可多拉也别在边界上少一个桶。
  weekly: { days: 90, unit: "周报", sparkLabel: "最近 12 周", sparkMax: 12 },
  monthly: { days: 90, unit: "月报", sparkLabel: "当月每日", sparkMax: 31 },
};

// ---------------------------------------------------------------- 日期工具

// 这些字符串已经是北京时间的日历日期，所以一律按 UTC 解析——只是借 Date 做日历
// 运算，不再涉及任何时区转换。再套一层本地时区反而会把日期算错。
const toDate = (s) => new Date(`${s}T00:00:00Z`);
const toStr = (d) => d.toISOString().slice(0, 10);

function addDays(s, n) {
  const d = toDate(s);
  d.setUTCDate(d.getUTCDate() + n);
  return toStr(d);
}

/** 周一为一周之始。 */
export function weekStart(s) {
  const d = toDate(s);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return toStr(d);
}

export function monthStart(s) {
  return `${s.slice(0, 7)}-01`;
}

function monthEnd(s) {
  const d = toDate(monthStart(s));
  d.setUTCMonth(d.getUTCMonth() + 1);
  d.setUTCDate(0);
  return toStr(d);
}

// ---------------------------------------------------------------- 分桶

/**
 * 把每日行聚合成周期桶，只保留**完整**的桶。
 *
 * 两头都要裁：最新那个桶通常还没走完（今天、本周、本月），最老那个桶可能被
 * 90 天窗口截断。留着它们会让环比和趋势图凭空出现一个矮柱，而那是取数窗口的
 * 形状，不是数据本身。
 *
 * @param rows  升序排列的每日行，形如 { date, <event>: n, ... }
 * @param today 北京时间的今天，YYYY-MM-DD
 */
export function bucketByPeriod(rows, period, today) {
  if (rows.length === 0) return [];
  const oldest = rows[0].date;

  const startOf = { daily: (s) => s, weekly: weekStart, monthly: monthStart }[
    period
  ];
  const endOf = {
    daily: (s) => s,
    weekly: (s) => addDays(weekStart(s), 6),
    monthly: monthEnd,
  }[period];
  if (!startOf) throw new Error(`Unknown period: ${period}`);

  const byStart = new Map();
  for (const row of rows) {
    const start = startOf(row.date);
    let bucket = byStart.get(start);
    if (!bucket) {
      bucket = { start, end: endOf(row.date), counts: {}, dates: [] };
      byStart.set(start, bucket);
    }
    bucket.dates.push(row.date);
    for (const [key, value] of Object.entries(row)) {
      if (key === "date") continue;
      bucket.counts[key] = (bucket.counts[key] ?? 0) + value;
    }
  }

  return [...byStart.values()]
    .filter((b) => b.end < today && b.start >= oldest)
    .sort((a, b) => (a.start < b.start ? -1 : 1));
}

// ---------------------------------------------------------------- 渲染

const BLOCKS = "▁▂▃▄▅▆▇█";

/**
 * 文本趋势图。
 *
 * 0 单独占最低一格，非零值从第二格起算——否则「今天没有」和「今天只有一个」
 * 会画成同一个高度，而这两件事在小数量级下差别很大。
 */
export function sparkline(values) {
  if (values.length === 0) return "";
  const max = Math.max(...values);
  if (max <= 0) return BLOCKS[0].repeat(values.length);
  const steps = BLOCKS.length - 2;
  return values
    .map((v) =>
      v <= 0 ? BLOCKS[0] : BLOCKS[1 + Math.round((v / max) * steps)]
    )
    .join("");
}

/** 环比。上期为 0 时不显示百分比——除以 0 得不出有意义的倍数。 */
export function formatDelta(current, previous) {
  if (previous === undefined || previous === null) return "";
  if (previous === 0) {
    return current > 0 ? ' <font color="green">新增</font>' : "";
  }
  const pct = Math.round(((current - previous) / previous) * 100);
  if (pct === 0) return ' <font color="grey">持平</font>';
  const color = pct > 0 ? "green" : "red";
  return ` <font color="${color}">${pct > 0 ? "+" : ""}${pct}%</font>`;
}

function ratio(counts, from, to) {
  const denominator = counts[from] ?? 0;
  const numerator = counts[to] ?? 0;
  if (denominator === 0) return null;
  return {
    pct: Math.round((numerator / denominator) * 100),
    numerator,
    denominator,
  };
}

function labelOf(bucket, period) {
  if (period === "daily") return bucket.start.slice(5).replace("-", "-");
  if (period === "weekly") return `${bucket.start.slice(5)} 那周`;
  return `${Number(bucket.start.slice(5, 7))} 月`;
}

/**
 * 渲染成飞书卡片。纯函数，不碰网络——卡片 JSON 很容易写错且往往只有线上才发现。
 */
export function buildReportCard({ period, buckets, dailyRows = [], repo }) {
  const config = PERIODS[period];
  if (!config) throw new Error(`Unknown period: ${period}`);

  if (buckets.length === 0) {
    return {
      schema: "2.0",
      header: {
        title: { tag: "plain_text", content: `埋点${config.unit} · 暂无完整数据` },
        template: "grey",
      },
      body: {
        elements: [
          {
            tag: "markdown",
            content: "取数窗口内还没有一个走完的周期，跳过本次。",
          },
        ],
      },
    };
  }

  const current = buckets[buckets.length - 1];
  const previous = buckets[buckets.length - 2];
  const sumDownloads = (counts) =>
    DOWNLOAD_CHANNELS.reduce((total, [event]) => total + (counts[event] ?? 0), 0);

  const lines = [];

  const headlines = [
    ["倒计时开始", (c) => c.countdown_start ?? 0],
    ["分享落地", (c) => c.share_land ?? 0],
    ["下载合计", sumDownloads],
  ];
  for (const [label, pick] of headlines) {
    const value = pick(current.counts);
    const delta = previous ? formatDelta(value, pick(previous.counts)) : "";
    lines.push(`${label} **${value}**${delta}`);
  }

  const channels = DOWNLOAD_CHANNELS.filter(
    ([event]) => (current.counts[event] ?? 0) > 0
  ).map(([event, name]) => `${name} ${current.counts[event]}`);
  if (channels.length > 0) {
    lines.push("");
    lines.push("**下载渠道**");
    lines.push(channels.join(" · "));
  }

  const ratios = RATIOS.map((r) => ({ ...r, value: ratio(current.counts, r.from, r.to) }))
    .filter((r) => r.value)
    .map(
      (r) =>
        `${r.label}：**${r.value.pct}%**（${r.value.numerator}/${r.value.denominator}）`
    );
  if (ratios.length > 0) {
    lines.push("");
    lines.push("**转化**（次数之比，非人数）");
    lines.push(...ratios);
  }

  // 月报的趋势用当月每日，比三个月柱子有信息量得多——90 天窗口最多只能凑出
  // 三个完整月，画成 3 个点看不出任何东西。
  const series =
    period === "monthly"
      ? dailyRows
          .filter((row) => row.date >= current.start && row.date <= current.end)
          .map((row) => ({ label: row.date, counts: row }))
      : buckets.slice(-config.sparkMax).map((b) => ({
          label: labelOf(b, period),
          counts: b.counts,
        }));

  if (series.length >= 2) {
    lines.push("");
    lines.push(`**${config.sparkLabel}**`);
    for (const [label, pick] of headlines) {
      lines.push(`${label} \`${sparkline(series.map((s) => pick(s.counts)))}\``);
    }
    lines.push(
      `<font color="grey">${series[0].label} → ${series[series.length - 1].label}</font>`
    );
  }

  if (repo) {
    lines.push("");
    lines.push(`<font color="grey">${repo}</font>`);
  }

  return {
    schema: "2.0",
    header: {
      title: {
        tag: "plain_text",
        content: `埋点${config.unit} · ${labelOf(current, period)}（北京时间）`,
      },
      template: "blue",
    },
    body: { elements: [{ tag: "markdown", content: lines.join("\n") }] },
  };
}

// ---------------------------------------------------------------- 取数

export async function fetchStats({
  baseUrl,
  token,
  days,
  fetchImpl = fetch,
}) {
  const response = await fetchImpl(`${baseUrl}/api/e/stats?days=${days}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    // 令牌没配时路由整个不存在，返回的就是 404——这是配置问题，不是取数失败，
    // 单独说清楚，否则排查时会去怀疑 Upstash。
    if (response.status === 404) {
      throw new Error(
        "/api/e/stats returned 404: ANALYTICS_STATS_TOKEN is unset on the deployment, or the token does not match."
      );
    }
    throw new Error(`/api/e/stats returned ${response.status}`);
  }
  const body = await response.json();
  if (!body.configured) return null;
  return [...body.days].sort((a, b) => (a.date < b.date ? -1 : 1));
}

// ---------------------------------------------------------------- 入口

if (import.meta.url === `file://${process.argv[1]}`) {
  const period = process.argv[2] ?? "daily";
  if (!PERIODS[period]) {
    console.error(`Unknown period: ${period}. Use daily, weekly or monthly.`);
    process.exit(1);
  }

  const webhook = process.env.LARK_WEBHOOK;
  const secret = process.env.LARK_SIGN_SECRET;
  const token = process.env.ANALYTICS_STATS_TOKEN;
  const baseUrl = (process.env.SITE_BASE_URL ?? DEFAULT_BASE_URL).replace(/\/$/, "");

  // 缺配置就安静退出，和 lark-notify.mjs 一致：本地和 fork 都拿不到 secrets，
  // 那不是错误。
  if (!webhook || !token) {
    console.log("LARK_WEBHOOK or ANALYTICS_STATS_TOKEN is not set; skipping report.");
    process.exit(0);
  }

  const rows = await fetchStats({ baseUrl, token, days: PERIODS[period].days });
  if (rows === null) {
    console.log("Analytics storage is not configured on the deployment; skipping report.");
    process.exit(0);
  }

  // 「今天」必须和分桶口径一致，用北京时间。
  const today = new Date(Date.now() + 8 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);

  const card = buildReportCard({
    period,
    buckets: bucketByPeriod(rows, period, today),
    dailyRows: rows,
    repo: process.env.GITHUB_REPOSITORY,
  });

  await sendCard(card, { webhook, secret });
  console.log(`Sent the ${period} analytics report.`);
}
