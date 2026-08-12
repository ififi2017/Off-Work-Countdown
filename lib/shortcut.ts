export type DesktopShortcutPlatform = "macos" | "windows" | "other";

export interface ShortcutKeyEvent {
  code: string;
  key: string;
  metaKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  shiftKey: boolean;
}

const MODIFIER_CODES = new Set([
  "MetaLeft",
  "MetaRight",
  "ControlLeft",
  "ControlRight",
  "AltLeft",
  "AltRight",
  "ShiftLeft",
  "ShiftRight",
]);

/** Convert a physical keyboard chord into the syntax used by Tauri's shortcut plugin. */
export function shortcutFromKeyEvent(event: ShortcutKeyEvent): string | null {
  if (MODIFIER_CODES.has(event.code) || event.key === "Dead") return null;
  const modifiers: string[] = [];
  if (event.metaKey) modifiers.push("Command");
  if (event.ctrlKey) modifiers.push("Control");
  if (event.altKey) modifiers.push("Alt");
  if (event.shiftKey) modifiers.push("Shift");
  if (modifiers.length === 0 || !event.code) return null;
  return [...modifiers, event.code].join("+");
}

function formatKeyToken(token: string): string {
  if (/^Key[A-Z]$/i.test(token)) return token.slice(3).toUpperCase();
  if (/^Digit[0-9]$/i.test(token)) return token.slice(5);
  const labels: Record<string, string> = {
    ArrowUp: "↑",
    ArrowDown: "↓",
    ArrowLeft: "←",
    ArrowRight: "→",
    Backquote: "`",
    Backslash: "\\",
    BracketLeft: "[",
    BracketRight: "]",
    Comma: ",",
    Equal: "=",
    Minus: "-",
    Period: ".",
    Quote: "'",
    Semicolon: ";",
    Slash: "/",
    Space: "Space",
  };
  return labels[token] ?? token.replace(/^Numpad/, "Num ");
}

export function formatDesktopShortcut(
  accelerator: string,
  platform: DesktopShortcutPlatform
): string {
  const tokens = accelerator.split("+").map((token) => token.trim());
  const mac = platform === "macos";
  return tokens
    .map((token) => {
      switch (token.toLowerCase()) {
        case "commandorcontrol":
        case "commandorctrl":
        case "cmdorctrl":
        case "cmdorcontrol":
          return mac ? "⌘" : "Ctrl";
        case "command":
        case "cmd":
        case "super":
          return mac ? "⌘" : "Win";
        case "control":
        case "ctrl":
          return mac ? "⌃" : "Ctrl";
        case "option":
        case "alt":
          return mac ? "⌥" : "Alt";
        case "shift":
          return mac ? "⇧" : "Shift";
        default:
          return formatKeyToken(token);
      }
    })
    .join(mac ? " " : " + ");
}
