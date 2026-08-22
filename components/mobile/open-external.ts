/**
 * Send a link to the system browser.
 *
 * `target="_blank"` is what Capacitor's WKWebView delegate turns into an
 * out-of-app open on iOS; navigating in place would strand the user inside the
 * app's own WebView with no way back. Keeping it in one helper also keeps every
 * external link going through the same path when a native bridge replaces it.
 */
export function openExternal(url: string): void {
  if (typeof window === "undefined") return;
  window.open(url, "_blank", "noopener,noreferrer");
}
