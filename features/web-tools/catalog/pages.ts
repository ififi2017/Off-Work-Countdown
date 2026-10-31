import { siteConfig } from "@/config/site";
import { CALCULATION_VERSION, type CalculationPurpose } from "../domain/salary";

export type ToolLanguage = "en" | "zh-CN";
export type ToolMarket = "cn" | "us";
export type SalaryTool = "overview" | "monthly-to-daily" | "monthly-to-hourly" | "workdays-21-75" | "hourly-to-annual" | "annual-to-hourly" | "biweekly-paycheck";
export interface ToolPage {
  id: string;
  kind: "salary" | "directory";
  lang: ToolLanguage;
  market?: ToolMarket;
  tool?: SalaryTool;
  slug: string[];
  path: string;
  title: string;
  description: string;
  equivalenceKey: string;
  toolId: string;
  purpose: CalculationPurpose | "directory";
  calculationVersion: string;
  sourcesReviewedAt: string | null;
  relatedPageIds: string[];
  status: "draft" | "reviewed" | "published" | "retired";
  contentReviewedAt: string | null;
}

function salary(lang: ToolLanguage, market: ToolMarket, tool: SalaryTool, title: string, description: string): ToolPage {
  const slug = tool === "overview" ? [] : [tool];
  return { id: `${market}-${tool}`, kind: "salary", lang, market, tool, slug,
    path: `/${lang}/salary/${market}${slug.length ? `/${slug[0]}` : ""}`,
    title, description, equivalenceKey: `${market}-${tool}`, toolId: "gross-salary",
    purpose: market === "cn" ? (tool === "monthly-to-hourly" ? "worked-time" : "jurisdiction-reference") : "annualized",
    calculationVersion: CALCULATION_VERSION, sourcesReviewedAt: market === "cn" ? "2026-10-31" : null,
    relatedPageIds: [], status: "published", contentReviewedAt: "2026-10-31" };
}

/** Initial CN/US batch approved for release by the user on 2026-10-31. */
export const pageRegistry: readonly ToolPage[] = [
  salary("zh-CN", "cn", "overview", "税前工资换算器", "换算月薪、年收入、日薪和时薪，区分年化换算、实际工时均摊与中国大陆21.75计薪参考。"),
  salary("zh-CN", "cn", "monthly-to-daily", "月薪换日薪：一天工资怎么算", "按21.75计薪日参考或自己填写的实际工作天数，将税前月薪换算为每天的金额。"),
  salary("zh-CN", "cn", "monthly-to-hourly", "月薪换时薪：每小时收入怎么算", "按同期工作天数和每天实际工作小时计算均摊时薪，并查看21.75×8小时的计薪参考。"),
  salary("zh-CN", "cn", "workdays-21-75", "21.75天怎么算：计薪日与工作日的区别", "了解21.75计薪日、20.67制度工作日和实际出勤天数的不同用途，并计算日工资与小时工资参考。"),
  salary("en", "us", "overview", "Gross salary calculator", "Convert hourly, annual and monthly gross pay with your paid hours, paid weeks and pay frequency. Compare annualized amounts before deductions."),
  salary("en", "us", "hourly-to-annual", "Hourly to annual salary calculator", "Convert an hourly rate to annual and monthly gross income using your paid hours per week and paid weeks per year."),
  salary("en", "us", "annual-to-hourly", "Annual salary to hourly calculator", "Find the hourly equivalent of an annual gross salary using your own weekly hours and paid weeks. Keep included bonuses from being counted twice."),
  salary("en", "us", "biweekly-paycheck", "Biweekly gross pay calculator", "Estimate average gross pay every two weeks and compare 26 biweekly payments with 24 semimonthly payments. This is not take-home pay."),
  ...(["en", "zh-CN"] as const).map((lang): ToolPage => ({
    id: `${lang}-tools`, kind: "directory", lang, slug: [], path: `/${lang}/tools`,
    title: lang === "en" ? "Work hours and gross pay tools" : "工时与税前工资工具库",
    description: lang === "en" ? "Calculate work hours, compare shift patterns and convert gross pay in your browser. Choose a tool and its calculation basis." : "在浏览器中计算工时、查看常见班次并换算税前工资，按问题选择工具和计算口径。",
    equivalenceKey: "tools-directory", toolId: "tools-directory", purpose: "directory", calculationVersion: CALCULATION_VERSION, sourcesReviewedAt: null, relatedPageIds: [], status: "published", contentReviewedAt: "2026-10-31",
  })),
];
for (const page of pageRegistry) {
  page.relatedPageIds = pageRegistry.filter((item) => item.kind === "salary" && item.lang === page.lang && item.id !== page.id).map((item) => item.id);
}

export const publishedPages = pageRegistry.filter((page) => page.status === "published");
export function getPublicPages(): readonly ToolPage[] { return publishedPages; }
export function getBuildPages(): readonly ToolPage[] {
  // Vercel production always wins over the local preview override.
  const preview = process.env.VERCEL_ENV !== "production"
    && (process.env.VERCEL_ENV === "preview" || process.env.WEB_TOOLS_PREVIEW === "1");
  return preview ? pageRegistry.filter((page) => page.status !== "retired") : publishedPages;
}
export function pageUrl(page: ToolPage): string { return `${siteConfig.webAppUrl}${page.path}`; }
export function getPageAlternates(pageOrId: ToolPage | string): Record<string, string> {
  const page = typeof pageOrId === "string" ? getBuildPages().find((item) => item.id === pageOrId) : pageOrId;
  if (!page || page.status !== "published") return {};
  // Language equivalence is explicit. A CN calculation is not a US translation.
  const peers = publishedPages.filter((item) => item.equivalenceKey === page.equivalenceKey);
  const fallback = peers.find((item) => item.lang === "en") ?? peers[0];
  return { ...Object.fromEntries(peers.map((item) => [item.market === "us" ? "en-US" : item.lang, pageUrl(item)])), ...(fallback ? { "x-default": pageUrl(fallback) } : {}) };
}
export function getSalaryPage(lang: string, market: string, slug: readonly string[] = []): ToolPage | undefined {
  return getBuildPages().find((page) => page.kind === "salary" && page.lang === lang && page.market === market && page.slug.join("/") === slug.join("/"));
}
export function getDirectoryPage(lang: string): ToolPage | undefined {
  return getBuildPages().find((page) => page.kind === "directory" && page.lang === lang);
}
export function getRelatedPages(page: ToolPage): readonly ToolPage[] {
  return getBuildPages().filter((item) => page.relatedPageIds.includes(item.id));
}
