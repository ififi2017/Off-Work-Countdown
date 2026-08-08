import { isTrackedEvent } from "@/lib/analytics-events";
import { incrementEvent } from "@/lib/server/analytics";

export const dynamic = "force-dynamic";

// 埋点接收端。sendBeacon 发来的是纯文本的事件名，这里只做白名单校验后计数。
//
// 无论校验结果、存储是否配置、写入是否成功，一律返回 204：客户端不需要知道
// 结果，也不该从响应里推断出后端配置。
export async function POST(request: Request) {
  const noContent = new Response(null, { status: 204 });

  try {
    // 限制读取长度，避免有人往这个公开端点灌大 body。
    const raw = await request.text();
    if (raw.length > 64) return noContent;

    const event = raw.trim();
    if (!isTrackedEvent(event)) return noContent;

    await incrementEvent(event);
  } catch {
    // 静默失败
  }

  return noContent;
}
