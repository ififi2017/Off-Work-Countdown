// Mood presets for the share image. Each mood maps an emoji to a gradient
// (hex color stops) used both for the canvas background and the picker preview.
// `labelKey` points at an i18n key in translation.json.

export interface Mood {
  id: string;
  emoji: string;
  /** Unicode codepoint, used to load the bundled PNG at /emoji/{code}.png for
   *  reliable rendering inside the canvas share image (system emoji don't
   *  rasterize to canvas on iOS Safari). */
  code: string;
  labelKey: string;
  /** 2+ hex color stops, drawn top-left → bottom-right. */
  gradient: string[];
}

export const moods: Mood[] = [
  { id: "excited", emoji: "🤩", code: "1f929", labelKey: "moodExcited", gradient: ["#a855f7", "#ec4899"] },
  { id: "happy", emoji: "😄", code: "1f604", labelKey: "moodHappy", gradient: ["#fbbf24", "#f97316"] },
  { id: "relaxed", emoji: "😌", code: "1f60c", labelKey: "moodRelaxed", gradient: ["#2dd4bf", "#22c55e"] },
  { id: "tired", emoji: "😫", code: "1f62b", labelKey: "moodTired", gradient: ["#6366f1", "#3b82f6"] },
  { id: "firedUp", emoji: "🔥", code: "1f525", labelKey: "moodFiredUp", gradient: ["#ef4444", "#f97316"] },
  { id: "celebrating", emoji: "🥳", code: "1f973", labelKey: "moodCelebrating", gradient: ["#f43f5e", "#f59e0b", "#22d3ee"] },
  { id: "coffee", emoji: "☕", code: "2615", labelKey: "moodCoffee", gradient: ["#b45309", "#d97706"] },
  { id: "counting", emoji: "😭", code: "1f62d", labelKey: "moodCounting", gradient: ["#06b6d4", "#3b82f6"] },
];

export const defaultMood: Mood = moods[0];

export function getMood(id: string | null | undefined): Mood {
  return moods.find((m) => m.id === id) ?? defaultMood;
}
