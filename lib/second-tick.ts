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
 *
 * 3. **不能正好卡在整秒上触发。** 浏览器的定时器可能提前约 1ms 触发（时钟精度
 *    被刻意降低），落在 x.999 时读到的仍是上一秒：同一个数显示两次，下一拍就
 *    一次掉两秒。Web 版数字有逐位过渡后，这个跳秒肉眼可见。所以瞄准整秒之后
 *    TICK_OFFSET_MS，若仍然提前落在整秒之前，就补等到边界再触发。
 */

/** 整秒之后再等这么久才触发，给定时器的提前 / 抖动留余量。 */
export const TICK_OFFSET_MS = 20;
export function startSecondTick(onTick: () => void): () => void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let cancelled = false;

  const schedule = () => {
    if (cancelled) return;
    // 距「下一个整秒 + TICK_OFFSET_MS」的毫秒数；刚过整秒不到 offset 时，
    // 就是本秒的那个触发点。
    const phase = Date.now() % 1000;
    const delay =
      phase < TICK_OFFSET_MS
        ? TICK_OFFSET_MS - phase
        : 1000 - phase + TICK_OFFSET_MS;
    timer = setTimeout(() => {
      if (cancelled) return;
      // 提前触发、还没跨过整秒（相位落在后半秒）：不读数，补等到边界之后。
      if (Date.now() % 1000 >= 500) {
        schedule();
        return;
      }
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
