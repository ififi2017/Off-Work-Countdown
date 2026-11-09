"use client";

import { Info } from "lucide-react";

/**
 * A small ⓘ that shows its explanation on hover (native tooltip) and reads it
 * out to screen readers. For secondary notes in the fixed 430pt Desktop
 * window, where a full sentence would push the main figures out of view.
 */
export function InfoHint({ text }: { text: string }) {
  return (
    <button
      type="button"
      title={text}
      aria-label={text}
      className="inline-flex h-5 w-5 shrink-0 cursor-help items-center justify-center rounded text-gray-400 transition-colors hover:text-gray-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-orange-400 dark:text-gray-500 dark:hover:text-gray-200"
    >
      <Info className="h-3.5 w-3.5" aria-hidden="true" />
    </button>
  );
}
