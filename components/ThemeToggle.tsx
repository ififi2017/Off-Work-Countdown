'use client';

import { Button } from "@/components/ui/button";
import { Moon, Sun } from "lucide-react";

interface ThemeToggleProps {
  theme: 'light' | 'dark' | 'auto';
  onToggle: () => void;
}

export function ThemeToggle({ theme, onToggle }: ThemeToggleProps) {
  return (
    <Button
      variant="ghost"
      size="icon"
      onClick={onToggle}
      className="w-9 h-9 p-0"
    >
      {theme === 'auto' ? (
        <div className="relative">
          {window.matchMedia('(prefers-color-scheme: dark)').matches ? <Moon size={20} /> : <Sun size={20} />}
          <span className="absolute -bottom-0.5 -right-0.5 bg-primary text-primary-foreground rounded-full w-3 h-3 flex items-center justify-center text-[7px] font-bold">A</span>
        </div>
      ) : theme === 'light' ? <Moon size={20} /> : <Sun size={20} />}
    </Button>
  );
} 