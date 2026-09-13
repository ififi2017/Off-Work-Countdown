// 截 Windows 形态的应用界面，存进 windows/raw/。截法见 ../desktop-capture.mjs。
// ?platform=windows 让主窗画应用自绘的最小化 / 关闭按钮，和 Windows 上真实的
// 样子一致，所以 compose 不需要补任何窗口装饰。
//
// 19 种界面语言，一一对应微软商店商品页的 19 个语言。第二项是系统 locale，
// 只影响托盘和菜单那类系统外壳文字。
import { captureDesktop } from "../desktop-capture.mjs";

await captureDesktop({
  platform: "windows",
  outDir: new URL("raw/", import.meta.url).pathname,
  languages: [
    ["en", "en-US"], ["zh-CN", "zh-CN"], ["zh-TW", "zh-TW"], ["zh-HK", "zh-HK"],
    ["ja", "ja-JP"], ["ko", "ko-KR"], ["de", "de-DE"], ["fr", "fr-FR"],
    ["es", "es-ES"], ["it", "it-IT"], ["pt", "pt-PT"], ["ru", "ru-RU"],
    ["hi-IN", "hi-IN"], ["mr-IN", "mr-IN"], ["tr", "tr-TR"], ["ar", "ar-SA"],
    ["th", "th-TH"], ["id", "id-ID"], ["vi", "vi-VN"],
  ],
});
