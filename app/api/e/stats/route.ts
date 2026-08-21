import { trackedEvents } from "@/lib/analytics-events";
import {
  eventDate,
  eventKey,
  readCounts,
  isAnalyticsConfigured,
} from "@/lib/server/analytics";

export const dynamic = "force-dynamic";

const DEFAULT_DAYS = 14;
const MAX_DAYS = 90;

// 读取最近若干天的事件计数，天按**北京时间**切分（见 lib/server/analytics.ts）。
// 用 Authorization 头传令牌而不是查询参数——
// 令牌是密钥，不该出现在 URL 里（会进日志、Referer 和浏览历史）。
//
//   curl -H "Authorization: Bearer $ANALYTICS_STATS_TOKEN" https://off.rainif.com/api/e/stats
//
// 未设置 ANALYTICS_STATS_TOKEN 时整个路由不存在，避免默认暴露。
export async function GET(request: Request) {
  const notFound = new Response("Not found", { status: 404 });

  const token = process.env.ANALYTICS_STATS_TOKEN;
  if (!token) return notFound;

  const provided = request.headers.get("authorization");
  if (provided !== `Bearer ${token}`) return notFound;

  if (!isAnalyticsConfigured()) {
    return Response.json({ configured: false, days: [] });
  }

  const requested = Number(new URL(request.url).searchParams.get("days"));
  const days =
    Number.isFinite(requested) && requested > 0
      ? Math.min(Math.floor(requested), MAX_DAYS)
      : DEFAULT_DAYS;

  const dates = Array.from({ length: days }, (_, i) => {
    const d = new Date();
    d.setUTCDate(d.getUTCDate() - i);
    return d;
  });

  const keys = dates.flatMap((d) =>
    trackedEvents.map((e) => eventKey(e, d))
  );

  try {
    const counts = await readCounts(keys);
    const rows = dates.map((d) => {
      // 用 eventDate 而不是 toISOString：键按北京时间分桶，标签必须同源，
      // 否则返回的是「UTC 日的标签配 CST 日的数字」。
      const date = eventDate(d);
      return {
        date,
        ...Object.fromEntries(
          trackedEvents.map((e) => [e, counts[eventKey(e, d)] ?? 0])
        ),
      };
    });
    return Response.json({ configured: true, days: rows });
  } catch {
    return new Response("Upstream error", { status: 502 });
  }
}
