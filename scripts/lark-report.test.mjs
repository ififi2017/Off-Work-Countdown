import { describe, expect, it } from "vitest";
import {
  bucketByPeriod,
  buildReportCard,
  fetchStats,
  formatDelta,
  monthStart,
  sparkline,
  weekStart,
} from "./lark-report.mjs";

/** 造一行每日数据，未指定的事件按 0 计。 */
function row(date, counts = {}) {
  return { date, countdown_start: 0, share_land: 0, ...counts };
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
    expect(text).toContain("Mac App Store 2");
    expect(text).not.toContain("Linux");
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
  it("explains a 404 as a missing token rather than a data problem", async () => {
    const fetchImpl = async () => ({ ok: false, status: 404 });
    await expect(
      fetchStats({ baseUrl: "https://example.com", token: "t", days: 15, fetchImpl })
    ).rejects.toThrow(/ANALYTICS_STATS_TOKEN/);
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
