/**
 * 对齐到墙上时钟整秒边界的自校正定时器。
 *
 * 不要用 `setInterval(fn, 1000)`：
 *
 * 1. **会累积漂移。** 每轮实际间隔是「回调耗时 + 1000ms」，久了就落后于真实时间。
 *    应用里有三个各自独立的计时器（主窗口、迷你窗、Rust 后台线程），起始相位又
 *    不同，于是同一时刻三处可以显示不同的秒数。
 * 2. **会跳秒。** 窗口失焦或被遮挡时 WebView 会节流定时器；某次 tick 迟到超过
 *    1000ms 时，`floor(剩余/1000)` 一次掉两秒——实测表现为 9 直接跳到 7。
 *
 * 每次都重新算到下一个整秒还差多少，误差就不会累积，各处也会落在同一个边界上。
 */
export function startSecondTick(onTick: () => void): () => void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let cancelled = false;

  const schedule = () => {
    if (cancelled) return;
    // 距下一个整秒的毫秒数。取 1 是为了避免 delay 为 0 时空转。
    const delay = Math.max(1, 1000 - (Date.now() % 1000));
    timer = setTimeout(() => {
      if (cancelled) return;
      onTick();
      schedule();
    }, delay);
  };

  schedule();

  return () => {
    cancelled = true;
    if (timer !== undefined) clearTimeout(timer);
  };
}
