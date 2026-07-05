// Mood presets for the share image. Each mood maps an emoji to a gradient
// (hex color stops) used both for the canvas background and the picker preview.
// `labelKey` points at an i18n key in translation.json.

export interface Mood {
  id: string;
  emoji: string;
  labelKey: string;
  /** 2+ hex color stops, drawn top-left → bottom-right. */
  gradient: string[];
}

export const moods: Mood[] = [
  { id: "excited", emoji: "🤩", labelKey: "moodExcited", gradient: ["#a855f7", "#ec4899"] },
  { id: "happy", emoji: "😄", labelKey: "moodHappy", gradient: ["#fbbf24", "#f97316"] },
  { id: "relaxed", emoji: "😌", labelKey: "moodRelaxed", gradient: ["#2dd4bf", "#22c55e"] },
  { id: "tired", emoji: "😫", labelKey: "moodTired", gradient: ["#6366f1", "#3b82f6"] },
  { id: "firedUp", emoji: "🔥", labelKey: "moodFiredUp", gradient: ["#ef4444", "#f97316"] },
  { id: "celebrating", emoji: "🥳", labelKey: "moodCelebrating", gradient: ["#f43f5e", "#f59e0b", "#22d3ee"] },
  { id: "coffee", emoji: "☕", labelKey: "moodCoffee", gradient: ["#b45309", "#d97706"] },
  { id: "counting", emoji: "😭", labelKey: "moodCounting", gradient: ["#06b6d4", "#3b82f6"] },
];

export const defaultMood: Mood = moods[0];

export function getMood(id: string | null | undefined): Mood {
  return moods.find((m) => m.id === id) ?? defaultMood;
}
