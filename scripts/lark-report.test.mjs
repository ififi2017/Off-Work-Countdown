import { describe, expect, it } from "vitest";
import { eventKey } from "@/lib/server/analytics";
import {
  KEY_PREFIX,
  bar,
  bucketByPeriod,
  buildReportCard,
  fetchStats,
  formatDelta,
  monthStart,
  parseEventKey,
  readStatsFromUpstash,
  sparkline,
  weekStart,
} from "./lark-report.mjs";

/** 造一行每日数据，未指定的事件按 0 计。 */
function row(date, counts = {}) {
  return { date, observed: true, countdown_start: 0, share_land: 0, ...counts };
}

/** 造一段连续日期。 */
function range(from, count, counts = () => ({})) {
  const out = [];
  const d = new Date(`${from}T00:00:00Z`);
  for (let i = 0; i < count; i++) {
    out.push(row(d.toISOString().slice(0, 10), counts(i)));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}

describe("weekStart", () => {
  it("anchors on Monday", () => {
    // 2026-08-21 是周五
    expect(weekStart("2026-08-21")).toBe("2026-08-17");
    expect(weekStart("2026-08-17")).toBe("2026-08-17");
    // 周日归属于它开始的那一周，不是下一周
    expect(weekStart("2026-08-23")).toBe("2026-08-17");
    expect(weekStart("2026-08-24")).toBe("2026-08-24");
  });
});

describe("monthStart", () => {
  it("returns the first day", () => {
    expect(monthStart("2026-08-21")).toBe("2026-08-01");
  });
});

describe("bucketByPeriod", () => {
  it("drops the still-running bucket at the newest edge", () => {
    const rows = range("2026-08-18", 4); // 18,19,20,21
    const buckets = bucketByPeriod(rows, "daily", "2026-08-21");
    // 21 号还没走完，不该出现在报表里
    expect(buckets.map((b) => b.start)).toEqual([
      "2026-08-18",
      "2026-08-19",
      "2026-08-20",
    ]);
  });

  it("drops a bucket truncated by the fetch window", () => {
    // 窗口从周三开始，那一周的周一、周二不在数据里——这个桶是残的，
    // 留着会在趋势图开头凭空多出一根矮柱。
    const rows = range("2026-08-19", 14); // 08-19 是周三
    const buckets = bucketByPeriod(rows, "weekly", "2026-09-02");
    expect(buckets.map((b) => b.start)).toEqual(["2026-08-24"]);
  });

  it("sums every event across the bucket", () => {
    const rows = range("2026-08-17", 7, () => ({ countdown_start: 3 }));
    const [week] = bucketByPeriod(rows, "weekly", "2026-08-24");
    expect(week.counts.countdown_start).toBe(21);
    expect(week.end).toBe("2026-08-23");
  });

  it("groups by calendar month", () => {
    const rows = [
      ...range("2026-07-01", 31, () => ({ share_land: 1 })),
      ...range("2026-08-01", 5, () => ({ share_land: 10 })),
    ];
    const buckets = bucketByPeriod(rows, "monthly", "2026-08-06");
    // 8 月还没走完，只剩 7 月
    expect(buckets).toHaveLength(1);
    expect(buckets[0].start).toBe("2026-07-01");
    expect(buckets[0].counts.share_land).toBe(31);
  });

  it("returns nothing when no bucket has completed", () => {
    expect(bucketByPeriod(range("2026-08-21", 1), "daily", "2026-08-21")).toEqual([]);
    expect(bucketByPeriod([], "daily", "2026-08-21")).toEqual([]);
  });

  it("rejects an unknown period", () => {
    expect(() => bucketByPeriod(range("2026-08-01", 3), "hourly", "2026-08-05")).toThrow(
      /Unknown period/
    );
  });
});

describe("sparkline", () => {
  it("keeps zero visually distinct from a small non-zero value", () => {
    const [zero, one] = sparkline([0, 1, 100]);
    expect(zero).toBe("▁");
    expect(one).not.toBe("▁");
  });

  it("puts the maximum at full height", () => {
    expect(sparkline([0, 5, 10]).at(-1)).toBe("█");
  });

  it("draws an all-zero series flat rather than crashing", () => {
    expect(sparkline([0, 0, 0])).toBe("▁▁▁");
    expect(sparkline([])).toBe("");
  });
});

describe("formatDelta", () => {
  it("does not divide by a zero baseline", () => {
    expect(formatDelta(5, 0)).toContain("新增");
    expect(formatDelta(0, 0)).toBe("");
  });

  it("colours growth and decline differently", () => {
    expect(formatDelta(110, 100)).toContain("green");
    expect(formatDelta(110, 100)).toContain("+10%");
    expect(formatDelta(90, 100)).toContain("red");
    expect(formatDelta(100, 100)).toContain("持平");
  });
});

describe("buildReportCard", () => {
  const buckets = (over) =>
    bucketByPeriod(range("2026-08-01", 20, over), "daily", "2026-08-21");

  it("compares against the previous bucket", () => {
    const card = buildReportCard({
      period: "daily",
      buckets: buckets((i) => ({ countdown_start: i })),
    });
    const text = card.body.elements[0].content;
    // 最后一个完整桶是 08-20（i=19），前一个是 i=18
    expect(text).toContain("倒计时开始 **19**");
    expect(text).toContain("+6%");
  });

  it("labels ratios as counts, not people", () => {
    const card = buildReportCard({
      period: "daily",
      buckets: buckets(() => ({
        share_land: 10,
        share_convert: 3,
      })),
    });
    const text = card.body.elements[0].content;
    expect(text).toContain("**30%**（3/10）");
    // 这套埋点拿不到人数，措辞必须说清楚，否则读报表的人会当成 UV
    expect(text).toContain("非人数");
  });

  it("omits a ratio whose denominator is zero", () => {
    const card = buildReportCard({ period: "daily", buckets: buckets() });
    expect(card.body.elements[0].content).not.toContain("分享落地 → 换成我的时间：");
  });

  it("lists only download channels that saw traffic", () => {
    const card = buildReportCard({
      period: "daily",
      buckets: buckets(() => ({ desktop_download_macappstore: 2 })),
    });
    const text = card.body.elements[0].content;
    expect(text).toContain("Mac App Store **2**");
    expect(text).not.toContain("Linux");
  });

  it("puts the busiest channel first and gives each its own line", () => {
    // 原来所有渠道挤在一行用「·」分隔，手机上折行后最大的和最小的混在一起，
    // 扫一眼看不出谁多谁少。
    const card = buildReportCard({
      period: "daily",
      buckets: buckets(() => ({
        desktop_download_msstore: 19,
        desktop_download_windows_intel: 31,
        desktop_download_macappstore: 1,
      })),
    });
    const channelLines = card.body.elements[0].content
      .split("\n")
      .filter((line) => /\*\*\d+\*\* `/.test(line));
    expect(channelLines.map((line) => line.split(" **")[0])).toEqual([
      "Windows x64",
      "微软商店",
      "Mac App Store",
    ]);
    // 最大的那条最长，最小的那条也得看得见
    expect(channelLines[0]).toMatch(/`█{12}`/);
    expect(channelLines[2]).toMatch(/`█`/);
  });

  it("says so plainly when no period has completed", () => {
    const card = buildReportCard({ period: "weekly", buckets: [] });
    expect(card.header.template).toBe("grey");
    expect(card.body.elements[0].content).toContain("跳过本次");
  });

  it("draws the monthly trend from that month's daily rows", () => {
    const rows = [
      ...range("2026-07-01", 31, (i) => ({ countdown_start: i })),
      ...range("2026-08-01", 3, () => ({ countdown_start: 999 })),
    ];
    const card = buildReportCard({
      period: "monthly",
      buckets: bucketByPeriod(rows, "monthly", "2026-08-04"),
      dailyRows: rows,
    });
    const text = card.body.elements[0].content;
    expect(text).toContain("当月每日");
    // 只覆盖 7 月的 31 天，不该把 8 月的行混进来
    const spark = text.match(/倒计时开始 `([^`]+)`/)[1];
    expect([...spark]).toHaveLength(31);
    expect(text).toContain("2026-07-01 → 2026-07-31");
  });

  it("rejects an unknown period", () => {
    expect(() => buildReportCard({ period: "hourly", buckets: [] })).toThrow(
      /Unknown period/
    );
  });
});

describe("fetchStats", () => {
  /** 造一个失败响应，headers.get 按真实 Response 的接口来。 */
  function failure(status, { body = "", headers = {} } = {}) {
    return {
      ok: false,
      status,
      headers: { get: (name) => headers[name.toLowerCase()] ?? null },
      text: async () => body,
    };
  }

  it("explains a 404 as a missing token rather than a data problem", async () => {
    const fetchImpl = async () => failure(404, { body: "Not found" });
    await expect(
      fetchStats({ baseUrl: "https://example.com", token: "t", days: 15, fetchImpl })
    ).rejects.toThrow(/ANALYTICS_STATS_TOKEN/);
  });

  it("blames the edge for a 403, not the token", async () => {
    // 路由本身对令牌不对只回 404，从不回 403——403 必然来自前置防护。
    // 不说清楚，排查方向会跑到 Upstash 上去。
    const fetchImpl = async () =>
      failure(403, {
        body: "<html>Error 1020 Access denied</html>",
        headers: { "cf-ray": "a2e6a0391e3cc40b-LAX", server: "cloudflare" },
      });
    const error = await fetchStats({
      baseUrl: "https://example.com",
      token: "t",
      days: 15,
      fetchImpl,
    }).catch((e) => e);
    expect(error.message).toMatch(/not a token problem/);
    expect(error.message).toContain("cf-ray=a2e6a0391e3cc40b-LAX");
    expect(error.message).toContain("Error 1020");
  });

  it("still reports a status when the body cannot be read", async () => {
    const fetchImpl = async () => ({
      ok: false,
      status: 502,
      headers: { get: () => null },
      text: async () => {
        throw new Error("stream closed");
      },
    });
    await expect(
      fetchStats({ baseUrl: "https://example.com", token: "t", days: 15, fetchImpl })
    ).rejects.toThrow(/returned 502/);
  });

  it("identifies itself instead of sending the default node UA", async () => {
    let seen;
    const fetchImpl = async (_url, init) => {
      seen = init.headers;
      return { ok: true, json: async () => ({ configured: true, days: [] }) };
    };
    await fetchStats({ baseUrl: "https://example.com", token: "t", days: 15, fetchImpl });
    expect(seen["User-Agent"]).toMatch(/off-work-countdown-report/);
    expect(seen["User-Agent"]).not.toBe("node");
  });

  it("returns null when the deployment has no storage configured", async () => {
    const fetchImpl = async () => ({
      ok: true,
      json: async () => ({ configured: false, days: [] }),
    });
    await expect(
      fetchStats({ baseUrl: "https://example.com", token: "t", days: 15, fetchImpl })
    ).resolves.toBeNull();
  });

  it("sorts rows oldest first", async () => {
    const fetchImpl = async () => ({
      ok: true,
      json: async () => ({
        configured: true,
        days: [row("2026-08-20"), row("2026-08-18"), row("2026-08-19")],
      }),
    });
    const rows = await fetchStats({
      baseUrl: "https://example.com",
      token: "t",
      days: 15,
      fetchImpl,
    });
    expect(rows.map((r) => r.date)).toEqual([
      "2026-08-18",
      "2026-08-19",
      "2026-08-20",
    ]);
  });
});

// 直连 Upstash 时键的格式在报表脚本里复制了一份。写入端一改而这边没跟上，
// 结果不是报错，而是读到一片不存在的键、报出全 0——最难发现的那种失败。
// 这组测试把两边钉在一起：直接拿写入端产出的键喂给读取端的解析器。
describe("键格式契约（与 lib/server/analytics.ts 对齐）", () => {
  it("parses exactly what the writer produces", () => {
    const key = eventKey("share_land", new Date("2026-08-21T02:00:00Z"));
    expect(key.startsWith(KEY_PREFIX)).toBe(true);
    expect(parseEventKey(key)).toEqual({
      date: "2026-08-21",
      event: "share_land",
    });
  });

  it("agrees with the writer on where a CST day starts", () => {
    // 2026-08-20T16:00Z 正好是北京时间 21 日 00:00
    expect(parseEventKey(eventKey("x", new Date("2026-08-20T15:59:00Z"))).date).toBe(
      "2026-08-20"
    );
    expect(parseEventKey(eventKey("x", new Date("2026-08-20T16:00:00Z"))).date).toBe(
      "2026-08-21"
    );
  });

  it("survives an event name containing a colon", () => {
    expect(parseEventKey(eventKey("a:b", new Date("2026-08-21T02:00:00Z")))).toEqual({
      date: "2026-08-21",
      event: "a:b",
    });
  });

  it("ignores keys that are not event counters", () => {
    expect(parseEventKey("other:2026-08-21:share_land")).toBeNull();
    expect(parseEventKey("e:not-a-date:share_land")).toBeNull();
    expect(parseEventKey("e:2026-08-21:")).toBeNull();
    expect(parseEventKey("e:2026-08-21")).toBeNull();
  });
});

describe("readStatsFromUpstash", () => {
  /**
   * 假的 Upstash。SCAN 刻意分成多页返回，并且中间夹一页空结果——真实的 SCAN
   * 就是这样：MATCH 过滤发生在服务端，某一轮扫到的槽位里一个都没命中很正常，
   * 此时游标还没到 0，不能就此收手。
   */
  function fakeRedis(keys, values, { pageSize = 1 } = {}) {
    const seen = [];
    const pages = [];
    for (let i = 0; i < keys.length; i += pageSize) {
      pages.push(keys.slice(i, i + pageSize));
    }
    pages.splice(1, 0, []); // 中间插一页空的
    const fetchImpl = async (_url, init) => {
      const command = JSON.parse(init.body);
      seen.push(command);
      if (command[0] === "SCAN") {
        const index = Number(command[1]);
        const batch = pages[index] ?? [];
        const next = index + 1 < pages.length ? String(index + 1) : "0";
        return { ok: true, json: async () => ({ result: [next, batch] }) };
      }
      const asked = command.slice(1);
      return {
        ok: true,
        json: async () => ({ result: asked.map((k) => values[k] ?? null) }),
      };
    };
    return { fetchImpl, seen };
  }

  it("keeps scanning past an empty page until the cursor comes back to 0", async () => {
    const { fetchImpl, seen } = fakeRedis(
      ["e:2026-08-19:share_land", "e:2026-08-20:share_land"],
      { "e:2026-08-19:share_land": "1", "e:2026-08-20:share_land": "2" }
    );
    const rows = await readStatsFromUpstash({
      url: "https://r.upstash.io",
      token: "t",
      days: 3,
      today: "2026-08-21",
      fetchImpl,
    });
    // 中间那页是空的，只取第一页或遇空即停都会漏掉后面的键
    expect(seen.filter((c) => c[0] === "SCAN").length).toBeGreaterThan(2);
    expect(rows.find((r) => r.date === "2026-08-20").share_land).toBe(2);
  });

  it("gives up rather than looping forever on a stuck cursor", async () => {
    const fetchImpl = async (_url, init) => {
      const command = JSON.parse(init.body);
      if (command[0] === "SCAN") {
        // 游标永远不回 0
        return { ok: true, json: async () => ({ result: ["99", []] }) };
      }
      return { ok: true, json: async () => ({ result: [] }) };
    };
    await expect(
      readStatsFromUpstash({
        url: "https://r.upstash.io",
        token: "t",
        days: 2,
        today: "2026-08-21",
        fetchImpl,
      })
    ).rejects.toThrow(/never returned to 0/);
  });

  it("discovers event names from the keys instead of hardcoding them", async () => {
    const { fetchImpl } = fakeRedis(
      ["e:2026-08-20:brand_new_event", "e:2026-08-20:share_land"],
      { "e:2026-08-20:brand_new_event": "7", "e:2026-08-20:share_land": "3" }
    );
    const rows = await readStatsFromUpstash({
      url: "https://r.upstash.io",
      token: "t",
      days: 2,
      today: "2026-08-21",
      fetchImpl,
    });
    // 白名单里还没有的事件也要出现——否则新加埋点后报表会静默漏掉它
    expect(rows.find((r) => r.date === "2026-08-20").brand_new_event).toBe(7);
  });

  it("fills quiet days with a row rather than leaving a gap", async () => {
    const { fetchImpl } = fakeRedis(["e:2026-08-20:share_land"], {
      "e:2026-08-20:share_land": "3",
    });
    const rows = await readStatsFromUpstash({
      url: "https://r.upstash.io",
      token: "t",
      days: 3,
      today: "2026-08-21",
      fetchImpl,
    });
    // 缺行会让趋势图少一格，看起来像那天没统计，而不是那天没人来
    expect(rows.map((r) => r.date)).toEqual([
      "2026-08-19",
      "2026-08-20",
      "2026-08-21",
    ]);
  });

  it("leaves keys outside the window alone", async () => {
    const { fetchImpl, seen } = fakeRedis(
      ["e:2020-01-01:share_land", "e:2026-08-20:share_land"],
      { "e:2026-08-20:share_land": "3" }
    );
    await readStatsFromUpstash({
      url: "https://r.upstash.io",
      token: "t",
      days: 2,
      today: "2026-08-21",
      fetchImpl,
    });
    const mget = seen.find((c) => c[0] === "MGET");
    expect(mget.slice(1)).toEqual(["e:2026-08-20:share_land"]);
  });

  it("skips MGET entirely when nothing matched", async () => {
    const { fetchImpl, seen } = fakeRedis([], {});
    const rows = await readStatsFromUpstash({
      url: "https://r.upstash.io",
      token: "t",
      days: 2,
      today: "2026-08-21",
      fetchImpl,
    });
    expect(seen.map((c) => c[0])).toEqual(["SCAN"]);
    expect(rows).toHaveLength(2);
  });

  it("surfaces an Upstash error instead of reporting zeros", async () => {
    const fetchImpl = async () => ({
      ok: true,
      json: async () => ({ error: "WRONGPASS invalid password" }),
    });
    await expect(
      readStatsFromUpstash({
        url: "https://r.upstash.io",
        token: "bad",
        days: 2,
        today: "2026-08-21",
        fetchImpl,
      })
    ).rejects.toThrow(/WRONGPASS/);
  });
});

// 「那一期是 0」和「那一期还没开始收数据」在计数上长得一模一样，但报出去的含义
// 完全相反。把没记录的一期当成 0 来比，会得出 +869% 这种纯属虚构的增长。
describe("没记录 ≠ 数据为 0", () => {
  const quiet = (date) => ({ date, observed: false });
  const busy = (date, n) => ({
    date,
    observed: true,
    countdown_start: n,
    share_land: 0,
  });

  it("counts only the days that actually left a record", () => {
    const [bucket] = bucketByPeriod(
      [quiet("2026-08-17"), busy("2026-08-18", 5), busy("2026-08-19", 5)],
      "weekly",
      "2026-08-24"
    );
    expect(bucket.observedDays).toBe(2);
    expect(bucket.counts.countdown_start).toBe(10);
  });

  it("does not let the observed flag corrupt the counts", () => {
    const [bucket] = bucketByPeriod([busy("2026-08-20", 3)], "daily", "2026-08-21");
    expect(bucket.counts.observed).toBeUndefined();
    expect(Number.isNaN(bucket.counts.countdown_start)).toBe(false);
  });

  it("refuses to report numbers for a period with no records at all", () => {
    const card = buildReportCard({
      period: "monthly",
      buckets: bucketByPeriod(
        [
          ...Array.from({ length: 31 }, (_, i) =>
            quiet(`2026-07-${String(i + 1).padStart(2, "0")}`)
          ),
        ],
        "monthly",
        "2026-08-05"
      ),
    });
    expect(card.header.template).toBe("grey");
    expect(card.body.elements[0].content).toContain("不是数据为 0");
    // 关键是不要把「0」当成事实报出去
    expect(card.body.elements[0].content).not.toContain("倒计时开始 **0**");
  });

  it("skips the delta when the previous period is only partly covered", () => {
    // 埋点上线那一周只有周末两天有数据，拿完整一周去比它会算出天文数字
    const rows = [
      ...Array.from({ length: 5 }, (_, i) =>
        quiet(`2026-08-${String(i + 10).padStart(2, "0")}`)
      ),
      busy("2026-08-15", 20),
      busy("2026-08-16", 20),
      ...Array.from({ length: 7 }, (_, i) => busy(`2026-08-${i + 17}`, 100)),
    ];
    const card = buildReportCard({
      period: "weekly",
      buckets: bucketByPeriod(rows, "weekly", "2026-08-24"),
    });
    const text = card.body.elements[0].content;
    expect(text).toContain("倒计时开始 **700**");
    expect(text).not.toMatch(/%/);
  });

  it("skips the delta when the previous period has no records", () => {
    const rows = [
      ...Array.from({ length: 7 }, (_, i) =>
        quiet(`2026-08-${String(i + 10).padStart(2, "0")}`)
      ),
      ...Array.from({ length: 7 }, (_, i) => busy(`2026-08-${i + 17}`, 100)),
    ];
    const card = buildReportCard({
      period: "weekly",
      buckets: bucketByPeriod(rows, "weekly", "2026-08-24"),
    });
    const text = card.body.elements[0].content;
    expect(text).toContain("倒计时开始 **700**");
    expect(text).not.toMatch(/%/); // 不该出现任何环比百分比
  });
});

describe("bar", () => {
  it("scales against the busiest channel", () => {
    expect(bar(100, 100)).toHaveLength(12);
    expect(bar(50, 100)).toHaveLength(6);
  });

  it("still draws something for a channel with a single download", () => {
    // 按比例算是 0 格，看着就像没有——但它出现在列表里本身就说明有
    expect(bar(1, 500)).toBe("█");
  });

  it("draws nothing for zero, and does not divide by zero", () => {
    expect(bar(0, 100)).toBe("");
    expect(bar(5, 0)).toBe("");
  });
});
