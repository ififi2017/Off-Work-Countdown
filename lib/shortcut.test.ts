import { describe, expect, it } from "vitest";
import { formatDesktopShortcut, shortcutFromKeyEvent } from "./shortcut";

describe("desktop shortcut helpers", () => {
  it("records a physical key with its modifiers", () => {
    expect(
      shortcutFromKeyEvent({
        code: "KeyK",
        key: "k",
        metaKey: true,
        ctrlKey: false,
        altKey: true,
        shiftKey: false,
      })
    ).toBe("Command+Alt+KeyK");
  });

  it("ignores bare keys and modifier-only keydowns", () => {
    expect(
      shortcutFromKeyEvent({
        code: "KeyK",
        key: "k",
        metaKey: false,
        ctrlKey: false,
        altKey: false,
        shiftKey: false,
      })
    ).toBeNull();
    expect(
      shortcutFromKeyEvent({
        code: "ShiftLeft",
        key: "Shift",
        metaKey: false,
        ctrlKey: false,
        altKey: false,
        shiftKey: true,
      })
    ).toBeNull();
  });

  it("uses native-looking labels on macOS and explicit labels on Windows", () => {
    expect(
      formatDesktopShortcut("CommandOrControl+Shift+KeyO", "macos")
    ).toBe("⌘ ⇧ O");
    expect(
      formatDesktopShortcut("CommandOrControl+Shift+KeyO", "windows")
    ).toBe("Ctrl + Shift + O");
  });
});
