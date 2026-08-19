import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { startSecondTick } from "./second-tick";

describe("startSecondTick", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("fires on the wall-clock second boundary, not a fixed interval", () => {
    vi.setSystemTime(new Date(1_700_000_000_250)); // 距下一个整秒还有 750ms
    const onTick = vi.fn();
    const stop = startSecondTick(onTick);

    vi.advanceTimersByTime(749);
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

    vi.advanceTimersByTime(1000);
    expect(onTick).toHaveBeenCalledTimes(1);
    // 回调让时间走到了 x.300，下一次应当只等 700ms 就回到整秒边界。
    vi.advanceTimersByTime(699);
    expect(onTick).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1);
    expect(onTick).toHaveBeenCalledTimes(2);
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
