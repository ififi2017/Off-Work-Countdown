export function isWindowsUserAgent(userAgent: string): boolean {
  return /windows nt/i.test(userAgent);
}
