// 截 Windows 形态的应用界面，存进 windows/raw/。截法见 ../desktop-capture.mjs。
// ?platform=windows 让主窗画应用自绘的最小化 / 关闭按钮，和 Windows 上真实的
// 样子一致，所以 compose 不需要补任何窗口装饰。
import { captureDesktop } from "../desktop-capture.mjs";

await captureDesktop({
  platform: "windows",
  outDir: new URL("raw/", import.meta.url).pathname,
});
