import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

// MSIX 那条产线上真正会悄悄漂的，是「清单里写的东西仓库里还在不在」这件事：
// 引用了一个 tauri icon 不再生成的图标、可执行文件改了名、版本忘了同步。
// 这些全都要等打 tag 触发发布、在 Windows runner 上跑到打包那一步才暴露。
//
// 它们本质上是数据一致性，不需要 Windows、不需要 exe、也不需要 winapp CLI，
// 所以放在单元测试里，每个 PR 都跑，几毫秒就能挡下来。

const MANIFEST = "src-tauri/msstore/Package.appxmanifest";
const ICON_DIR = "src-tauri/icons";

const manifest = readFileSync(MANIFEST, "utf8");
const storeConfig = JSON.parse(
  readFileSync("src-tauri/tauri.msstore.conf.json", "utf8")
);
const productVersion = JSON.parse(readFileSync("package.json", "utf8")).version;

describe("Microsoft Store package manifest", () => {
  it("references only icons that exist", () => {
    const assets = [
      ...new Set(
        [...manifest.matchAll(/Assets\\([A-Za-z0-9._-]+)/g)].map((m) => m[1])
      ),
    ];
    expect(assets.length).toBeGreaterThan(0);
    for (const asset of assets) {
      expect(existsSync(`${ICON_DIR}/${asset}`), `${ICON_DIR}/${asset}`).toBe(
        true
      );
    }
  });

  it("declares the executable the store build actually produces", () => {
    // bundle.active 为 false 时 Tauri 不改名，靠 mainBinaryName 把产物名定成
    // 带空格的 "Off Work Countdown"。两边对不上打出来的包能装、点开却没反应。
    const declared = manifest.match(
      /<Application\b[^>]*\bExecutable="([^"]+)"/
    )?.[1];
    expect(declared).toBe(`${storeConfig.mainBinaryName}.exe`);
  });

  it("keeps the startup task pointing at the same executable", () => {
    const startup = manifest.match(
      /<uap5:Extension\b[^>]*\bExecutable="([^"]+)"/
    )?.[1];
    expect(startup).toBe(`${storeConfig.mainBinaryName}.exe`);
  });

  it("carries a four-part version whose store segment stays zero", () => {
    const version = manifest.match(/<Identity[\s\S]*?\bVersion="([^"]+)"/)?.[1];
    expect(version).toBe(`${productVersion}.0`);
  });

  it("lists the default language first", () => {
    // 商店产品页的「支持的语言」读这份声明，而默认语言必须排在最前。
    const languages = [
      ...manifest.matchAll(/<Resource Language="([^"]+)"/g),
    ].map((m) => m[1]);
    expect(languages[0]).toBe("en-us");
    expect(languages.length).toBeGreaterThan(1);
  });

  it("declares every locale the app ships", () => {
    // 少声明一种，商店页面就会少标一种，而这一栏是用户判断「有没有我的语言」
    // 的唯一依据。
    const declared = new Set(
      [...manifest.matchAll(/<Resource Language="([^"]+)"/g)].map((m) =>
        m[1].toLowerCase()
      )
    );
    const uiLocales = readFileSync("i18n-config.ts", "utf8")
      .match(/locales = \[([\s\S]*?)\]/)?.[1]
      .match(/"([^"]+)"/g)
      .map((s) => s.replaceAll('"', ""));

    expect(uiLocales.length).toBe(19);
    expect(declared.size).toBe(uiLocales.length);
  });
});
