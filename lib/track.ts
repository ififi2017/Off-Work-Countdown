import type { TrackedEvent } from "./analytics-events";
import { IS_WEB_BUILD } from "./build-target";

// 客户端埋点。用 navigator.sendBeacon 而不是 fetch：它由浏览器在后台发送，
// 页面卸载或跳转时也不会被打断，且不会阻塞导航。
//
// 不引入任何依赖，不写 cookie，不带任何标识——只把事件名发出去，服务端做计数。
// 任何失败都静默吞掉：埋点绝不能影响正常使用。
export function track(event: TrackedEvent): void {
  // 静态壳不回传任何数据：包里没有 /api/e，且分享漏斗本就是 Web 端的概念。
  if (!IS_WEB_BUILD) return;
  if (typeof navigator === "undefined" || !navigator.sendBeacon) return;
  try {
    navigator.sendBeacon("/api/e", event);
  } catch {
    // 忽略：埋点失败不值得打扰用户
  }
}
