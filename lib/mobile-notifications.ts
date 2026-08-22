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

export async function openDesktopNotificationSettings(): Promise<void> {}

export async function showNotification(): Promise<boolean> {
  return false;
}
