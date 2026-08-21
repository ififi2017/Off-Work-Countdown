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

// 分桶按**北京时间**切天，不是 UTC。报表是给人看的，「昨天」必须和读报表的人
// 心里的昨天是同一天；按 UTC 切，早上收到的「昨日数据」实际覆盖前天 08:00 到
// 昨天 08:00，每次解读都要在脑子里做一次时区换算。
//
// 用固定 +8 而不是 Intl/时区库：中国自 1991 年起不实行夏令时，UTC+8 恒定成立，
// 为此拉一个时区数据库不划算。
//
// ⚠️ 这个偏移是**写入时**决定的，历史数据无法回算：库里存的是整日计数，没有更
// 细的粒度，切换点之前的键仍然是 UTC 日。跨越切换点的趋势会有一次性的 8 小时
// 错位，此后一致。
const CST_OFFSET_MS = 8 * 60 * 60 * 1000;

/** 某个时刻落在哪个北京时间日期，返回 YYYY-MM-DD。 */
export function eventDate(date = new Date()): string {
  return new Date(date.getTime() + CST_OFFSET_MS).toISOString().slice(0, 10);
}

/** 事件计数按天分桶：e:2026-08-08:share_land（日期为北京时间） */
export function eventKey(event: string, date = new Date()): string {
  return `e:${eventDate(date)}:${event}`;
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
