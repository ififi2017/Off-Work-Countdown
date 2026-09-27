import { describe, expect, it, vi } from "vitest";
import { buildSync } from "esbuild";
import { runInNewContext } from "node:vm";

const code = buildSync({
  entryPoints: ["src-extension/bootstrap.ts"],
  bundle: true,
  write: false,
  format: "iife",
  platform: "browser",
}).outputFiles[0].text;

function openPopup() {
  const callbacks = new Map<string, () => void>();
  const tasks: (() => void)[] = [];
  const resources: {
    tag: string;
    rel?: string;
    href?: string;
    src?: string;
    onload?: () => void;
    onerror?: () => void;
  }[] = [];
  const marks: string[] = [];
  const elements = Object.fromEntries(
    ["boot", "boot-status", "boot-retry"].map((id) => [
      id,
      {
        textContent: "",
        hidden: true,
        onclick: () => {},
        setAttribute: vi.fn(),
      },
    ]),
  );
  const reload = vi.fn();
  runInNewContext(code, {
    window: {
      addEventListener: (name: string, callback: () => void) =>
        callbacks.set(name, callback),
    },
    document: {
      documentElement: { classList: { add() {}, remove() {} } },
      body: { classList: { add() {}, remove() {} } },
      createElement: (tag: string) => ({ tag }),
      getElementById: (id: string) => elements[id],
      head: {
        append: (element: (typeof resources)[number]) =>
          resources.push(element),
      },
    },
    localStorage: { getItem: () => null },
    matchMedia: () => ({ matches: false }),
    location: { reload },
    chrome: {
      i18n: {
        getMessage: (key: string) =>
          ({ loadError: "加载失败", reload: "重新加载" })[key],
      },
    },
    performance: { mark: (name: string) => marks.push(name) },
    setTimeout: (callback: () => void) => tasks.push(callback),
  });
  return { callbacks, tasks, resources, elements, reload, marks };
}

describe("Chrome popup visibility gate", () => {
  it("finishes the window load event before requesting the app or its resources", () => {
    const page = openPopup();
    expect(page.resources).toEqual([]);
    expect(page.tasks).toHaveLength(0);
    page.callbacks.get("load")!();
    // The load handler must return before the expensive app can start.
    expect(page.resources).toEqual([]);
    expect(page.tasks).toHaveLength(1);
    page.tasks[0]();
    expect(page.resources).toHaveLength(1);
    expect(page.resources[0]).toMatchObject({
      tag: "link",
      href: "popup.css",
      rel: "stylesheet",
    });
    page.resources[0].onload!();
    expect(page.resources[1]).toMatchObject({
      tag: "script",
      src: "popup.js",
      type: "module",
    });
    expect(page.marks).toEqual([
      "doneat:bootstrap",
      "doneat:window-load",
      "doneat:app-request",
    ]);
  });

  it.each(["stylesheet", "script"])(
    "offers a localized reload when the %s cannot load",
    (resource) => {
      const page = openPopup();
      page.callbacks.get("load")!();
      page.tasks[0]();
      if (resource === "script") page.resources[0].onload!();
      page.resources.at(-1)!.onerror!();
      expect(page.elements["boot-status"].textContent).toBe("加载失败");
      expect(page.elements["boot"].setAttribute).toHaveBeenCalledWith(
        "aria-busy",
        "false",
      );
      expect(page.elements["boot-retry"].hidden).toBe(false);
      expect(page.elements["boot-retry"].textContent).toBe("重新加载");
      page.elements["boot-retry"].onclick();
      expect(page.reload).toHaveBeenCalledOnce();
    },
  );
});
