"use client";

import { motion, AnimatePresence } from "framer-motion";
import { Theme } from "./ThemeToggle";

interface BackgroundProps {
  theme: Theme;
}

export function Background({ theme }: BackgroundProps) {
  const getBackgroundStyle = (theme: Theme) => {
    switch (theme) {
      case "cyberpunk":
        return {
          background: "linear-gradient(135deg, #2b1055, #7597de)",
          backgroundSize: "400% 400%",
        };
      case "sunset":
        return {
          background: "linear-gradient(135deg, #ff9a9e, #fecfef, #feada6)",
          backgroundSize: "400% 400%",
        };
      default:
        return null; // Let the CSS class handle solid colors
    }
  };

  const bgStyle = getBackgroundStyle(theme);

  return (
    <div className="fixed inset-0 -z-10 overflow-hidden pointer-events-none">
      <AnimatePresence mode="popLayout">
        {bgStyle && (
          <motion.div
            key={theme}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 1, ease: "easeInOut" }}
            className="absolute inset-0 bg-gradient-animate"
            style={bgStyle}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
