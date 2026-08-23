// P1 bridge surface. P3 replaces these no-op results with the native
// UNUserNotificationCenter scheduler; Mobile must never fall back to the Web
// Notification or Service Worker APIs.
export interface NotificationPermissionResult {
  granted: boolean;
  newlyGranted: boolean;
}

export async function requestNotificationPermissionDetailed(): Promise<NotificationPermissionResult> {
  return { granted: false, newlyGranted: false };
}

export async function requestNotificationPermission(): Promise<boolean> {
  return false;
}

/**
 * P1 has no notification bridge yet, so the answer is "unavailable" rather than
 * "denied". The Settings screen only offers to open system settings on a real
 * refusal; reporting one here would tell every user they had turned
 * notifications off when in fact the platform has not been wired up.
 */
export async function getNotificationPermission(): Promise<
  NotificationPermission | "unavailable"
> {
  return "unavailable";
}

export async function openDesktopNotificationSettings(): Promise<void> {}

export async function showNotification(): Promise<boolean> {
  return false;
}
