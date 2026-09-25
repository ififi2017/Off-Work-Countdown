"use client";

import { useEffect, useRef, useState, type CSSProperties } from "react";
import { Theme } from "./ThemeToggle";

interface BackgroundProps {
  theme: Theme;
}

const GRADIENTS: Partial<Record<Theme, CSSProperties>> = {
  cyberpunk: {
    background: "linear-gradient(135deg, #2b1055, #7597de)",
    backgroundSize: "400% 400%",
  },
  sunset: {
    background: "linear-gradient(135deg, #ff9a9e, #fecfef, #feada6)",
    backgroundSize: "400% 400%",
  },
};

const FADE_MS = 1000;

interface Layer {
  id: number;
  theme: Theme;
  visible: boolean;
}

// 渐变主题的背景层，用 CSS opacity 过渡做交叉淡入淡出。
//
// 此前用 framer-motion 的 AnimatePresence：它在动画结束的那一帧会把 opacity
// 先弹回起始值再落定（淡出的层闪回全不透明、淡入的层闪成透明），切到赛博朋克 /
// 日落时「快结束时闪一下」就是这一帧。CSS 过渡由浏览器合成，不会有这一跳。
//
// 过渡规则：
// - 新渐变叠在旧渐变上面淡入，旧层保持不透明，等新层完全盖住再移除；
// - 从渐变切回浅色 / 深色时，渐变层淡出，露出页面自己的底色；
// - 页面外层是层叠上下文（isolate），这一层画在它的底色之上、内容之下。
export function Background({ theme }: BackgroundProps) {
  const [layers, setLayers] = useState<Layer[]>([]);
  const nextId = useRef(0);

  useEffect(() => {
    if (GRADIENTS[theme]) {
      const id = ++nextId.current;
      setLayers((prev) => [...prev, { id, theme, visible: false }]);
      // 先让 opacity: 0 真正画出来一帧，再切到 1，过渡才会从 0 开始。
      let second = 0;
      const first = requestAnimationFrame(() => {
        second = requestAnimationFrame(() =>
          setLayers((prev) =>
            prev.map((layer) => (layer.id === id ? { ...layer, visible: true } : layer))
          )
        );
      });
      const cleanup = window.setTimeout(
        () => setLayers((prev) => prev.filter((layer) => layer.id >= id)),
        FADE_MS + 50
      );
      return () => {
        cancelAnimationFrame(first);
        cancelAnimationFrame(second);
        window.clearTimeout(cleanup);
      };
    }

    setLayers((prev) => prev.map((layer) => ({ ...layer, visible: false })));
    const cleanup = window.setTimeout(() => setLayers([]), FADE_MS + 50);
    return () => window.clearTimeout(cleanup);
  }, [theme]);

  return (
    <div className="fixed inset-0 -z-10 overflow-hidden pointer-events-none">
      {layers.map((layer) => (
        <div
          key={layer.id}
          className="absolute inset-0 bg-gradient-animate transition-opacity ease-in-out motion-reduce:transition-none"
          style={{
            ...GRADIENTS[layer.theme],
            opacity: layer.visible ? 1 : 0,
            transitionDuration: `${FADE_MS}ms`,
            zIndex: layer.id,
            willChange: "opacity",
          }}
        />
      ))}
    </div>
  );
}
