import { applySavedTheme } from "@/lib/theme";

// Chrome keeps action popups hidden until the document's load event completes.
// Do not import the app, preload its font, or wait for requestAnimationFrame
// here: the hidden renderer must be able to finish loading the small shell.
performance.mark("doneat:bootstrap");
applySavedTheme(matchMedia("(prefers-color-scheme: dark)").matches);

function showLoadError() {
  const messages = (
    globalThis as typeof globalThis & {
      chrome?: { i18n?: { getMessage: (key: string) => string } };
    }
  ).chrome?.i18n;
  const status = document.getElementById("boot-status")!;
  status.textContent =
    messages?.getMessage("loadError") || "DoneAt couldn’t open. Please reload.";
  status.setAttribute("role", "alert");
  const retry = document.getElementById("boot-retry")!;
  retry.textContent = messages?.getMessage("reload") || "Reload";
  retry.hidden = false;
  retry.onclick = () => location.reload();
  document.getElementById("boot")!.setAttribute("aria-busy", "false");
}

function loadApp() {
  performance.mark("doneat:app-request");
  const styles = document.createElement("link");
  styles.rel = "stylesheet";
  styles.href = "popup.css";
  styles.onerror = showLoadError;
  styles.onload = () => {
    const script = document.createElement("script");
    script.type = "module";
    script.src = "popup.js";
    script.onerror = showLoadError;
    document.head.append(script);
  };
  document.head.append(styles);
}

window.addEventListener(
  "load",
  () => {
    performance.mark("doneat:window-load");
    // A new task lets Chrome process DocumentOnLoadCompleted and show the window
    // before React, translations, and the app's modules execute.
    setTimeout(loadApp, 0);
  },
  { once: true },
);
