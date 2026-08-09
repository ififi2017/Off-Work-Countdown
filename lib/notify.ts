const IS_DESKTOP_BUILD = process.env.NEXT_PUBLIC_BUILD_TARGET === "desktop";

export async function requestNotificationPermission(): Promise<boolean> {
  if (IS_DESKTOP_BUILD) {
    try {
      const { isPermissionGranted, requestPermission } = await import(
        "@tauri-apps/plugin-notification"
      );
      if (await isPermissionGranted()) return true;
      return (await requestPermission()) === "granted";
    } catch {
      return false;
    }
  }

  if (typeof window === "undefined" || !("Notification" in window)) return false;
  if (Notification.permission === "granted") return true;
  if (Notification.permission === "denied") return false;
  return (await Notification.requestPermission()) === "granted";
}

// 通知发送。桌面构建走 Tauri 原生通知；Web 端优先走 Service Worker 注册，
// 再退回页面级 Notification 构造函数。
//
// 为什么优先用 SW：Android Chrome 上 `new Notification()` 会直接抛
// TypeError，只允许通过 registration.showNotification() 发送。原实现把这个
// 异常吞掉了，结果是安卓用户根本收不到提醒，而且毫无迹象。
//
// 用 getRegistration() 而不是 serviceWorker.ready：后者在没有注册 SW 时
// 永远不 resolve（开发环境下 Serwist 是关闭的），会把调用方挂死。

export async function showNotification(
  title: string,
  body: string
): Promise<boolean> {
  if (IS_DESKTOP_BUILD) {
    try {
      const { isPermissionGranted, sendNotification } = await import(
        "@tauri-apps/plugin-notification"
      );
      if (!(await isPermissionGranted())) return false;
      sendNotification({ title, body });
      return true;
    } catch {
      return false;
    }
  }

  if (typeof window === "undefined" || !("Notification" in window)) return false;
  if (Notification.permission !== "granted") return false;

  const options: NotificationOptions = {
    body,
    icon: "/icon-192x192.png",
    badge: "/icon-192x192.png",
    // 同一 tag 的通知会互相替换，避免重复提醒堆叠在通知中心
    tag: "off-work-reminder",
  };

  try {
    const registration = await navigator.serviceWorker?.getRegistration();
    if (registration) {
      await registration.showNotification(title, options);
      return true;
    }
  } catch {
    // 落到下面的兜底
  }

  try {
    new Notification(title, options);
    return true;
  } catch {
    return false;
  }
}
