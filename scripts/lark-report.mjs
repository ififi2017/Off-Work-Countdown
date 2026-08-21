#!/usr/bin/env node

/**
 * 埋点日报 / 周报 / 月报，推送到飞书。
 *
 * 复用 lark-notify.mjs 的自定义机器人通道（签名算法那个坑已经在那边踩过并注释）。
 * 天按北京时间切分，见 lib/server/analytics.ts。
 *
 * 取数有两条路，配了 Upstash 就直连，否则走 HTTP：
 *
 *   直连 Upstash —— GitHub Actions 的 runner 是数据中心 IP，站点前面的 Cloudflare
 *     默认按 bot 拦截，/api/e/stats 在 CI 里拿到的是 403。直连绕开整条公网链路，
 *     也不再依赖站点本身是否可用。
 *   HTTP /api/e/stats —— 本地调试、以及自部署时前面没有 WAF 的场合。
 *
 * ⚠️ 直连意味着键的格式在这里复制了一份。lib/server/analytics.ts 一改，这边会
 * 静默读到不存在的键、报出一片 0，而不是报错——这种失败最难发现。所以
 * scripts/lark-report.test.mjs 里有一个契约测试直接 import 那个 TS 的 eventKey，
 * 两边对不上就红。改键格式时别绕过它。
 *
 * ⚠️ 这套埋点是刻意的**纯聚合计数**：不写 cookie、不记 IP、不带任何标识。所以
 * 报表只能给「事件发生了多少次」和事件之间的比率，给不了 UV、留存，也给不了
 * 「同一批人」的漏斗——两个事件的比值是次数比，不是人数比。措辞别写成人数。
 */

import { sendCard } from "./lark-notify.mjs";

const DEFAULT_BASE_URL = "https://off.rainif.com";
const REPORT_USER_AGENT = "off-work-countdown-report/1.0";

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
 * @param rows  升序排列的每日行，形如 { date, observed, <event>: n, ... }
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
      bucket = {
        start,
        end: endOf(row.date),
        counts: {},
        dates: [],
        // 「那天有没有留下任何键」。全 0 和「当时还没开始收」在计数上长得一模
        // 一样，但一个是事实、一个是没有事实，报表里必须分开。
        observedDays: 0,
      };
      byStart.set(start, bucket);
    }
    bucket.dates.push(row.date);
    if (row.observed) bucket.observedDays += 1;
    for (const [key, value] of Object.entries(row)) {
      // 只累加计数字段。date 是字符串、observed 是布尔，混进来会把桶算成 NaN。
      if (key === "date" || typeof value !== "number") continue;
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

  const newest = buckets[buckets.length - 1];
  if (buckets.length === 0 || newest.observedDays === 0) {
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
            content:
              buckets.length === 0
                ? "取数窗口内还没有一个走完的周期，跳过本次。"
                : "这个周期一条记录都没有——是当时还没开始收，不是数据为 0，所以不报数字。",
          },
        ],
      },
    };
  }

  const current = buckets[buckets.length - 1];
  // 上一期完全没有记录时不做环比：拿有数据的一期去除以没数据的一期，会得出
  // +869% 这种看着惊人、其实只是「那时候还没开始收」的数字。
  // 只跟**每一天都有记录**的上一期比。埋点上线那一周只覆盖了两天，拿完整一周
  // 去除以它会得出 +869%：算得对，含义是假的。宁可不显示环比。
  const rawPrevious = buckets[buckets.length - 2];
  const previous =
    rawPrevious && rawPrevious.observedDays === rawPrevious.dates.length
      ? rawPrevious
      : undefined;
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

/** 键形如 e:2026-08-21:share_land，前缀与 lib/server/analytics.ts 的 eventKey 一致。 */
export const KEY_PREFIX = "e:";

/** 从键名反解出日期和事件名。格式对不上返回 null，避免把别的键混进报表。 */
export function parseEventKey(key) {
  if (!key.startsWith(KEY_PREFIX)) return null;
  const rest = key.slice(KEY_PREFIX.length);
  const separator = rest.indexOf(":");
  if (separator <= 0) return null;
  const date = rest.slice(0, separator);
  const event = rest.slice(separator + 1);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !event) return null;
  return { date, event };
}

async function upstash(command, { url, token, fetchImpl }) {
  const response = await fetchImpl(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(command),
  });
  if (!response.ok) {
    throw new Error(
      `Upstash ${command[0]} returned ${response.status}: ${(await response.text()).slice(0, 200)}`
    );
  }
  const body = await response.json();
  if (body.error) throw new Error(`Upstash ${command[0]} failed: ${body.error}`);
  return body.result;
}

/**
 * 遍历所有事件键。
 *
 * 用 SCAN 而不是 KEYS：Upstash 的默认 REST token 直接拒掉 KEYS
 * （`NOPERM this user has no permissions to run the 'keys' command`），
 * 换成 SCAN 才跑得通——这是拿真库试出来的，不是照文档猜的。
 *
 * SCAN 必须循环到游标回到 "0"，只取第一页会静默漏数据；MATCH 和 COUNT 都只是
 * 提示，某一轮返回空数组不代表扫完了。
 */
async function scanEventKeys({ url, token, fetchImpl }) {
  const keys = [];
  let cursor = "0";
  // 防呆上限：真实数据量是「事件数 × 天数」，千级；真跑满说明游标没在推进。
  for (let round = 0; round < 1000; round++) {
    const [next, batch] = await upstash(
      ["SCAN", cursor, "MATCH", `${KEY_PREFIX}*`, "COUNT", "1000"],
      { url, token, fetchImpl }
    );
    keys.push(...(batch ?? []));
    cursor = String(next);
    if (cursor === "0") return keys;
  }
  throw new Error("Upstash SCAN did not finish; the cursor never returned to 0.");
}

/**
 * 直接从 Upstash 读最近 days 天。
 *
 * 事件名靠扫键得到，而不是在这里再抄一份 trackedEvents：抄一份就多一处会悄悄
 * 过时的东西，而漏掉一个新加的事件同样是静默失败。库很小（实测 144 个键），
 * 扫一遍的代价可以忽略。
 *
 * 返回的形状与 HTTP 那条路一致，好让后面的分桶和渲染只认一种输入。窗口内没有
 * 任何事件的日子也会补一行 0——否则趋势图会缺格，看起来像那天没统计。
 */
export async function readStatsFromUpstash({
  url,
  token,
  days,
  today,
  fetchImpl = fetch,
}) {
  const base = url.replace(/\/$/, "");
  const oldest = addDays(today, -(days - 1));

  const keys = await scanEventKeys({ url: base, token, fetchImpl });

  const wanted = [];
  for (const key of keys) {
    const parsed = parseEventKey(key);
    if (parsed && parsed.date >= oldest && parsed.date <= today) {
      wanted.push({ key, ...parsed });
    }
  }

  const byDate = new Map();
  for (let i = 0; i < days; i++) {
    const date = addDays(oldest, i);
    byDate.set(date, { date, observed: false });
  }

  if (wanted.length > 0) {
    const values = await upstash(["MGET", ...wanted.map((w) => w.key)], {
      url: base,
      token,
      fetchImpl,
    });
    wanted.forEach((w, i) => {
      const row = byDate.get(w.date);
      if (!row) return;
      row[w.event] = Number(values?.[i] ?? 0) || 0;
      // 键存在本身就是证据：那天埋点确实在跑。
      row.observed = true;
    });
  }

  return [...byDate.values()].sort((a, b) => (a.date < b.date ? -1 : 1));
}


export async function fetchStats({
  baseUrl,
  token,
  days,
  fetchImpl = fetch,
}) {
  const response = await fetchImpl(`${baseUrl}/api/e/stats?days=${days}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      // Node 的 fetch 默认发 `User-Agent: node`，很多 WAF 会因此提高警惕。
      // 报上真实身份既不吃亏，被拦时对方的日志里也能看出是谁。
      "User-Agent": `${REPORT_USER_AGENT} (+https://github.com/ififi2017/Off-Work-Countdown)`,
    },
  });
  if (!response.ok) {
    throw new Error(await describeFailure(response));
  }
  const body = await response.json();
  if (!body.configured) return null;
  // HTTP 那条路分不出「没记录」和「真的是 0」——端点对缺失的键一律返回 0，
  // 信息在那一层就丢了。只能一律当作有记录，代价是这条路上的环比可能虚高。
  return [...body.days]
    .map((row) => ({ ...row, observed: true }))
    .sort((a, b) => (a.date < b.date ? -1 : 1));
}

/**
 * 把一次失败的取数翻译成能直接照着排查的话。
 *
 * 这个端点前面隔着 Cloudflare，所以失败可能发生在两个完全不同的地方，而它们的
 * 修法毫不相干：路由自己只会用 404 表示「令牌不对」，其余状态码基本都是被前置
 * 防护拦下的。只抛一个裸状态码会让人去翻 Upstash，方向就错了。
 *
 * 响应体和 cf-ray 一起带上——Cloudflare 的拦截页里写着是哪条规则干的。
 */
async function describeFailure(response) {
  const ray = response.headers?.get?.("cf-ray");
  const server = response.headers?.get?.("server");
  let body = "";
  try {
    body = (await response.text()).replace(/\s+/g, " ").trim().slice(0, 300);
  } catch {
    // 读不出来就算了，状态码本身已经是主要线索
  }
  const suffix = [
    body && `body="${body}"`,
    server && `server=${server}`,
    ray && `cf-ray=${ray}`,
  ]
    .filter(Boolean)
    .join(" ");

  if (response.status === 404) {
    return `/api/e/stats returned 404: ANALYTICS_STATS_TOKEN is unset on the deployment, or the token does not match. ${suffix}`;
  }
  if (response.status === 403 || response.status === 429) {
    return (
      `/api/e/stats returned ${response.status}: this is the edge (Cloudflare/WAF) rejecting the runner, ` +
      `not a token problem — the route itself answers 404 for a bad token and never 403. ` +
      `GitHub Actions runners come from datacenter IPs that bot protection blocks by default; ` +
      `add a skip/bypass rule for this path. ${suffix}`
    );
  }
  return `/api/e/stats returned ${response.status}. ${suffix}`;
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
  const statsToken = process.env.ANALYTICS_STATS_TOKEN;
  const redisUrl = process.env.UPSTASH_REDIS_REST_URL;
  const redisToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  const baseUrl = (process.env.SITE_BASE_URL ?? DEFAULT_BASE_URL).replace(/\/$/, "");

  // 缺配置就安静退出，和 lark-notify.mjs 一致：本地和 fork 都拿不到 secrets，
  // 那不是错误。
  const canRead = (redisUrl && redisToken) || statsToken;
  if (!webhook || !canRead) {
    console.log(
      "LARK_WEBHOOK, or both data sources, are unset; skipping report."
    );
    process.exit(0);
  }

  // 「今天」必须和分桶口径一致，用北京时间。
  const today = new Date(Date.now() + 8 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);

  let rows;
  if (redisUrl && redisToken) {
    rows = await readStatsFromUpstash({
      url: redisUrl,
      token: redisToken,
      days: PERIODS[period].days,
      today,
    });
  } else {
    rows = await fetchStats({
      baseUrl,
      token: statsToken,
      days: PERIODS[period].days,
    });
    if (rows === null) {
      console.log(
        "Analytics storage is not configured on the deployment; skipping report."
      );
      process.exit(0);
    }
  }

  const card = buildReportCard({
    period,
    buckets: bucketByPeriod(rows, period, today),
    dailyRows: rows,
    repo: process.env.GITHUB_REPOSITORY,
  });

  await sendCard(card, { webhook, secret });
  console.log(`Sent the ${period} analytics report.`);
}
