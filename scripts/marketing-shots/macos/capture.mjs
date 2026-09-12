// 截 macOS 形态的应用界面，存进 macos/raw/。截法见 ../desktop-capture.mjs。
// 与 Windows 那套的区别只在 platform：主窗按覆盖式标题栏给交通灯留出顶部空间
// （真正的交通灯由 macOS 画，浏览器里是空的，由 compose.mjs 按真实位置补上）。
//
// 17 种界面语言，一一对应 App Store 的 17 个商店语言（映射见 app-store-connect/
// mac-os 下的版本配置）。第二项是系统 locale，只影响托盘和菜单那类系统外壳文字。
import { captureDesktop } from "../desktop-capture.mjs";

await captureDesktop({
  platform: "macos",
  outDir: new URL("raw/", import.meta.url).pathname,
  languages: [
    ["en", "en-US"], ["zh-CN", "zh-CN"], ["zh-TW", "zh-TW"], ["ja", "ja-JP"],
    ["ko", "ko-KR"], ["de", "de-DE"], ["es", "es-ES"], ["fr", "fr-FR"],
    ["it", "it-IT"], ["pt", "pt-BR"], ["ru", "ru-RU"], ["ar", "ar-SA"],
    ["hi-IN", "hi-IN"], ["id", "id-ID"], ["th", "th-TH"], ["tr", "tr-TR"],
    ["vi", "vi-VN"],
  ],
});
