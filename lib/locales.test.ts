import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { locales } from "../i18n-config";

const loadTranslation = (locale: string): Record<string, unknown> =>
  JSON.parse(
    readFileSync(
      `${process.cwd()}/public/locales/${locale}/translation.json`,
      "utf8"
    )
  );

const loadSeo = (locale: string): Record<string, string> =>
  JSON.parse(
    readFileSync(`${process.cwd()}/public/locales/${locale}/seo.json`, "utf8")
  );

// 002 P1 走查发现 89 个新 key 里有 74–82 个在非中文语种里还是英文原文：
// 界面导航是德语，Paywall、图表、Life、Focus 全是英文。逐个 key 看没人能发现，
// 因为每一行单独看都"像已经填过了"。这里的哨兵是：值和英文逐字相同就要解释。
//
// 允许相同的只有三类，其他一律视为漏翻：
// 1. 品牌与产品名（DoneAt Plus、Face ID、Woodfish 皮肤名）。
// 2. 目标语言里本来就借用英文的词（法语/意大利语的 Focus，德语的 Status）。
// 3. 纯符号或数字排版模板（{{start}} – {{end}}）。
const SAME_AS_ENGLISH_ON_PURPOSE: Record<string, "*" | readonly string[]> = {
  // 品牌、产品名与平台名
  getAppPlatforms: "*",
  liveActivity: ["id"],
  woodfishSkin: [
    "ar",
    "de",
    "es",
    "fr",
    "hi-IN",
    "id",
    "it",
    "mr-IN",
    "pt",
    "ru",
    "th",
    "tr",
  ],
  cyberpunk: ["de", "es", "fr", "id", "it", "pt", "vi"],
  standardSkin: ["de", "fr"],
  meritGain: ["de", "es", "fr", "id", "it", "pt", "tr"],
  faq: ["de", "fr"],
  // 纯排版模板：只有分隔符和占位符
  recordsAllocationTap: "*",
  timeLeft: ["de", "es", "fr", "it", "pt"],
  minutesShort: ["es", "fr", "it", "pt"],
  minutesUnit: ["es", "fr", "it", "pt"],
  // 目标语言里通用的英文借词
  recordsFocus: ["fr", "it"],
  timerTab: ["de", "id", "it"],
  version: ["de", "fr"],
  auto: ["de"],
  inTime: ["de"],
  shareTabLink: ["de", "it", "pt"],
  shareTabText: ["de"],
  shareTabImage: ["fr"],
  shareFormatStory: ["fr"],
  shiftSection: ["id"],
  trayMiniTimer: ["it"],
  disabledShort: ["it"],
  menuFile: ["id", "it"],
  menuEdit: ["id"],
  menuZoom: ["es", "fr", "id", "it", "pt"],
  menuServices: ["fr"],
};

const mayMatchEnglish = (key: string, locale: string): boolean => {
  const allowed = SAME_AS_ENGLISH_ON_PURPOSE[key];
  if (!allowed) return false;
  return allowed === "*" || allowed.includes(locale);
};

const placeholders = (value: string): string[] =>
  [...value.matchAll(/\{\{(\w+)\}\}/g)].map((match) => match[1]).sort();

describe("UI locale resources", () => {
  it("keeps every user-facing key available in all 19 locales", () => {
    const referenceKeys = Object.keys(loadTranslation("en")).sort();

    for (const locale of locales) {
      expect(Object.keys(loadTranslation(locale)).sort(), locale).toEqual(
        referenceKeys
      );
    }
  });

  // 019 L2b 把只有 iOS 用的键移出了这些文件。代码点名的键缺了，界面上显示的
  // 是键名本身，任何构建都不会报错，所以在这里逐个核对。只看字面量调用；
  // `landingFeature${n}` 这类拼出来的键不在这条的覆盖范围内。
  it("defines every key the Web and Desktop code names", () => {
    const sources = (dir: string): string[] =>
      readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const path = join(dir, entry.name);
        if (entry.isDirectory()) return entry.name === "node_modules" ? [] : sources(path);
        return /\.(ts|tsx)$/.test(entry.name) && !/\.test\./.test(entry.name) ? [path] : [];
      });
    const en = loadTranslation("en");
    const missing = new Set<string>();
    for (const file of ["app", "components", "lib"].flatMap(sources)) {
      const code = readFileSync(file, "utf8");
      for (const match of code.matchAll(/\bt\(\s*["'`]([A-Za-z][A-Za-z0-9_]*)["'`]/g)) {
        if (!(match[1] in en)) missing.add(`${file}: ${match[1]}`);
      }
    }
    expect([...missing]).toEqual([]);
  });

  it("only allows English copy for keys that still exist", () => {
    const en = loadTranslation("en");
    expect(
      Object.keys(SAME_AS_ENGLISH_ON_PURPOSE).filter((key) => !(key in en))
    ).toEqual([]);
  });

  it("does not leave English copy sitting in the other 18 locales", () => {
    const en = loadTranslation("en");

    for (const locale of locales) {
      if (locale === "en") continue;
      const translation = loadTranslation(locale);
      const untranslated = Object.keys(en).filter((key) => {
        const english = en[key];
        if (typeof english !== "string") return false;
        if (translation[key] !== english) return false;
        return !mayMatchEnglish(key, locale);
      });

      expect(untranslated, `${locale} still shows English copy`).toEqual([]);
    }
  });

  it("keeps interpolation placeholders identical across locales", () => {
    const en = loadTranslation("en");

    for (const locale of locales) {
      const translation = loadTranslation(locale);
      for (const [key, english] of Object.entries(en)) {
        if (typeof english !== "string") continue;
        const translated = translation[key];
        expect(typeof translated, `${locale} ${key}`).toBe("string");
        expect(placeholders(String(translated)), `${locale} ${key}`).toEqual(
          placeholders(english)
        );
      }
    }
  });

  it("keeps the plural variants of a key in step with its base form", () => {
    // i18next 的 `_one` 后缀补单数，不带后缀的 key 充当 other 形式。这条哨兵
    // 盯两件事：19 个语种都要有变体（少一个就会回落到英文），以及有屈折的
    // 语种必须真的换词，不能照抄复数。
    //
    // 唯一用过它的 recordsMonthWorkdays 只在 iOS 上出现，019 L2b 起随 iOS
    // 文案迁到 Localizable.xcstrings，由 scripts/check-ios-strings.mjs 按同样
    // 的规则检查。这里暂时没有 `_one` 键，哨兵留给 Web 以后的复数。
    const INFLECTS_FOR_ONE = [
      "en",
      "de",
      "es",
      "fr",
      "it",
      "pt",
      "ru",
      "hi-IN",
      "mr-IN",
    ];
    const en = loadTranslation("en");
    const pluralKeys = Object.keys(en).filter((key) => key.endsWith("_one"));

    for (const variantKey of pluralKeys) {
      const baseKey = variantKey.slice(0, -"_one".length);
      expect(Object.keys(en), `${baseKey} lost its other form`).toContain(
        baseKey
      );

      for (const locale of locales) {
        const translation = loadTranslation(locale);
        const singular = translation[variantKey];
        expect(typeof singular, `${locale} ${variantKey}`).toBe("string");

        const differs = singular !== translation[baseKey];
        expect(differs, `${locale} ${variantKey}`).toBe(
          INFLECTS_FOR_ONE.includes(locale)
        );
      }
    }
  });

  it("keeps one merged health reminder set in every locale", () => {
    // 喝水和起身合并成单个健康提醒时，只有 zh-CN 和 en 跟上了，其余 15 个
    // 语种在两个版本里一直留着合并前的六条。条数一致是这件事最省事的哨兵。
    const referenceLength = (
      loadTranslation("en").microBreakMessages as unknown[]
    ).length;

    for (const locale of locales) {
      const messages = loadTranslation(locale).microBreakMessages;
      expect(Array.isArray(messages), locale).toBe(true);
      expect(messages, locale).toHaveLength(referenceLength);
      for (const message of messages as unknown[]) {
        expect(typeof message, locale).toBe("string");
        expect(String(message), locale).toContain("{{minutes}}");
        expect(String(message), locale).not.toContain("{{salary}}");
        expect(String(message), locale).not.toContain("{{earnings}}");
      }
    }
  });

  it("provides five rotating notification tones without salary placeholders", () => {
    for (const locale of locales) {
      const translation = loadTranslation(locale);
      const tones = translation.notificationToneMessages;
      expect(Array.isArray(tones), locale).toBe(true);
      expect(tones, locale).toHaveLength(5);
      expect(
        (tones as unknown[]).every(
          (item) => typeof item === "string" && item.length > 0
        ),
        locale
      ).toBe(true);

      for (const milestone of [50, 75, 90, 95]) {
        const message = translation[`notificationMilestone${milestone}`];
        expect(typeof message, `${locale} ${milestone}`).toBe("string");
        expect(String(message), `${locale} ${milestone}`).not.toContain("{{");
      }

      // 标题是唯一带百分比的地方：正文里 90% 和 95% 两句意思一样，
      // 数字掉了就分不出走到哪一档了。
      const title = String(translation.notificationMilestoneTitle);
      expect(title, locale).toContain("{{percent}}");
      expect(title, locale).not.toContain("{{salary}}");
      expect(title, locale).not.toContain("{{earnings}}");

      const completion = String(translation.notificationMilestone100);
      expect(completion, locale).toContain("{{today}}");
      expect(completion, locale).toContain("{{year}}");
      expect(completion, locale).not.toContain("{{salary}}");
      expect(completion, locale).not.toContain("{{earnings}}");
    }
  });
});

describe("SEO locale resources", () => {
  it("uses DoneAt and describes the browser timer, not a full shift planner", () => {
    for (const locale of locales) {
      const seo = loadSeo(locale);
      expect(seo.siteName, locale).toBe("DoneAt");
      expect(seo.title, locale).toMatch(/^DoneAt — /);
      expect(seo.keywords.toLowerCase(), locale).toContain("doneat");
    }

    expect(loadSeo("en").title).toMatch(/browser/i);
    expect(loadSeo("zh-CN").title).toContain("浏览器");
    expect(loadSeo("en").keywords).toContain("off work countdown");
    expect(loadSeo("zh-CN").keywords).toContain("下班倒计时");
  });

  it("drops empty productivity slogans from home meta", () => {
    const banned = [
      /workplace productivity/i,
      /work-life balance/i,
      /提升职场效率/,
      /平衡工作与生活/,
    ];

    for (const locale of locales) {
      const text = `${loadSeo(locale).title}\n${loadSeo(locale).description}`;
      for (const pattern of banned) {
        expect(text, locale).not.toMatch(pattern);
      }
    }
  });
});
