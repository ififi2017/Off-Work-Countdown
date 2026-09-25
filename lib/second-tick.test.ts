import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TICK_OFFSET_MS, startSecondTick } from "./second-tick";

describe("startSecondTick", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("fires just after the wall-clock second boundary, not a fixed interval", () => {
    vi.setSystemTime(new Date(1_700_000_000_250)); // 距下一个整秒还有 750ms
    const onTick = vi.fn();
    const stop = startSecondTick(onTick);

    vi.advanceTimersByTime(750 + TICK_OFFSET_MS - 1);
    expect(onTick).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(onTick).toHaveBeenCalledTimes(1);

    // 下一次应当在整整 1000ms 之后，而不是从回调返回时重新数 1000ms。
    vi.advanceTimersByTime(999);
    expect(onTick).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1);
    expect(onTick).toHaveBeenCalledTimes(2);
    stop();
  });

  it("re-aligns instead of accumulating drift when a tick runs late", () => {
    vi.setSystemTime(new Date(1_700_000_000_000));
    const onTick = vi.fn(() => {
      // 模拟一次耗时 300ms 的回调——setInterval 会把这 300ms 累加成漂移。
      vi.setSystemTime(new Date(Date.now() + 300));
    });
    const stop = startSecondTick(onTick);

    vi.advanceTimersByTime(TICK_OFFSET_MS);
    expect(onTick).toHaveBeenCalledTimes(1);
    // 回调让时间走到了 x.320，下一次应当回到下一个整秒 + offset。
    vi.advanceTimersByTime(699);
    expect(onTick).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1);
    expect(onTick).toHaveBeenCalledTimes(2);
    stop();
  });

  it("does not sample the old second when a timer fires just before the boundary", () => {
    vi.setSystemTime(new Date(1_700_000_000_100));
    const seconds: number[] = [];
    const stop = startSecondTick(() => seconds.push(Math.floor(Date.now() / 1000)));

    // 定时器按 920ms 后（x.020）排好了；把系统时钟拨慢 21ms，模拟浏览器提前
    // 触发：回调执行时读到的是 x-1.999，仍是上一秒。
    vi.setSystemTime(new Date(1_700_000_000_100 - 21));
    vi.advanceTimersByTime(920);
    expect(Date.now() % 1000).toBe(999);
    expect(seconds).toEqual([]);

    vi.advanceTimersByTime(2000);
    // 每一秒恰好一次，不重复、不跳过。
    expect(seconds).toEqual([1_700_000_001, 1_700_000_002]);
    stop();
  });

  it("stops firing after the returned disposer runs", () => {
    vi.setSystemTime(new Date(1_700_000_000_000));
    const onTick = vi.fn();
    startSecondTick(onTick)();
    vi.advanceTimersByTime(5000);
    expect(onTick).not.toHaveBeenCalled();
  });
});
