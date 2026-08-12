"use client";

import { useEffect, useRef } from "react";

/** 每项高度与可见行数决定滚轮的观感；两者一起决定容器高度和上下留白。 */
const ITEM_HEIGHT = 34;
const VISIBLE_ROWS = 5;
const PADDING = ((VISIBLE_ROWS - 1) / 2) * ITEM_HEIGHT;

interface WheelPickerProps {
  items: string[];
  value: string;
  /** 滚动落定时提交。只提交，不关闭——否则滚动过程中菜单会自己消失。 */
  onChange: (value: string) => void;
  /** 点击某一项时提交。点击是明确的「就它了」，调用方通常顺手收起菜单。 */
  onSelect?: (value: string) => void;
  ariaLabel: string;
}

/**
 * iOS 闹钟式滚轮。选中项固定在中间，上下都露出相邻值，所以纵向空间是被
 * 两边一起用起来的，而不是像下拉菜单那样只往一个方向铺。
 *
 * 用原生滚动 + CSS scroll-snap 实现，不自己接管指针事件：这样滚轮、触控板
 * 惯性、拖拽和键盘翻页全部照常工作，也不需要处理它们之间的冲突。
 */
export function WheelPicker({
  items,
  value,
  onChange,
  onSelect,
  ariaLabel,
}: WheelPickerProps) {
  const listRef = useRef<HTMLDivElement>(null);
  const settleTimerRef = useRef<number | null>(null);
  // 记住最后一次「对外报出」的值，避免滚动过程中反复触发同一个值。
  const reportedRef = useRef(value);

  // 打开时把选中项直接摆到中间。这里必须是瞬时定位而不是平滑滚动，否则
  // 每次打开都要看一段无意义的滑动动画。
  useEffect(() => {
    const list = listRef.current;
    if (!list) return;
    const index = items.indexOf(value);
    if (index < 0) return;
    list.scrollTop = index * ITEM_HEIGHT;
    reportedRef.current = value;
  }, [items, value]);

  useEffect(() => {
    return () => {
      if (settleTimerRef.current) window.clearTimeout(settleTimerRef.current);
    };
  }, []);

  const handleScroll = () => {
    const list = listRef.current;
    if (!list) return;
    if (settleTimerRef.current) window.clearTimeout(settleTimerRef.current);
    // 滚动停下来之后才提交：滚动途中每经过一项就提交一次，会把中间划过的
    // 每个值都写进设置里。
    settleTimerRef.current = window.setTimeout(() => {
      const index = Math.round(list.scrollTop / ITEM_HEIGHT);
      const next = items[Math.min(items.length - 1, Math.max(0, index))];
      if (next && next !== reportedRef.current) {
        reportedRef.current = next;
        onChange(next);
      }
    }, 90);
  };

  return (
    <div className="relative" style={{ height: VISIBLE_ROWS * ITEM_HEIGHT }}>
      {/* 中间的选中带。放在滚动层下面并且不吃指针事件，纯粹是视觉参考线。 */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-1 top-1/2 -translate-y-1/2 rounded-lg bg-accent/60"
        style={{ height: ITEM_HEIGHT }}
      />
      <div
        ref={listRef}
        role="listbox"
        aria-label={ariaLabel}
        tabIndex={0}
        onScroll={handleScroll}
        className="wheel-picker-scroll h-full overflow-y-auto overscroll-contain focus:outline-none"
        style={{
          scrollSnapType: "y mandatory",
          paddingBlock: PADDING,
          // 上下淡出，暗示列表还在继续，而不是被硬切断。
          maskImage:
            "linear-gradient(to bottom, transparent, black 22%, black 78%, transparent)",
          WebkitMaskImage:
            "linear-gradient(to bottom, transparent, black 22%, black 78%, transparent)",
        }}
      >
        {items.map((item) => (
          <div
            key={item}
            role="option"
            aria-selected={item === value}
            onClick={() => {
              // 点击后要立刻同步 reportedRef：这次提交会让 value 变化，
              // 进而触发居中的 scrollTop 赋值，滚动回调随后会再算一次索引。
              // 不先记下来的话那次回调会把同一个值再提交一遍。
              reportedRef.current = item;
              (onSelect ?? onChange)(item);
            }}
            className={`flex cursor-pointer items-center justify-center text-sm tabular-nums transition-colors ${
              item === value
                ? "font-semibold text-foreground"
                : "text-muted-foreground"
            }`}
            style={{ height: ITEM_HEIGHT, scrollSnapAlign: "center" }}
          >
            {item}
          </div>
        ))}
      </div>
    </div>
  );
}
