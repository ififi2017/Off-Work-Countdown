import Link from "next/link";
import { notFound } from "next/navigation";
import { getBuildPages, getDirectoryPage, getRelatedPages, getSalaryPage } from "@/features/web-tools/catalog/pages";
import { toolPageJsonLd, toolPageMetadata } from "@/features/web-tools/catalog/metadata";
import { SalaryCalculator } from "@/features/web-tools/components/SalaryCalculator";
import { ToolPageFrame } from "@/features/web-tools/components/ToolPageFrame";
import { formatMoney } from "@/features/web-tools/content/calculator";
import { getPublicExampleResults, getSalaryContent } from "@/features/web-tools/content/salary-pages";
import { cnPayReference } from "@/features/web-tools/markets/cn";

export const dynamicParams = false;
type PageParams = { lang: string; market: string; slug?: string[] };
export function generateStaticParams() {
  return getBuildPages().filter((page) => page.kind === "salary").map((page) => ({ lang: page.lang, market: page.market, slug: page.slug }));
}
export async function generateMetadata({ params }: { params: Promise<PageParams> }) {
  const { lang, market, slug } = await params;
  const page = getSalaryPage(lang, market, slug);
  return page ? toolPageMetadata(page) : { robots: { index: false, follow: false } };
}
export default async function SalaryPage({ params }: { params: Promise<PageParams> }) {
  const { lang, market, slug } = await params;
  const page = getSalaryPage(lang, market, slug);
  if (!page) notFound();
  const zh = lang === "zh-CN";
  const content = getSalaryContent(page);
  const examples = getPublicExampleResults(page);
  const related = getRelatedPages(page);
  const directory = getDirectoryPage(lang);
  const linkClass = "text-orange-700 underline decoration-orange-700/30 underline-offset-4 hover:decoration-orange-700 dark:text-orange-400";
  return <ToolPageFrame page={page}>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(toolPageJsonLd(page)).replace(/</g, "\\u003c") }} />
    <p className="mt-4 max-w-3xl text-base leading-7 text-gray-600 dark:text-gray-300">{content.intro}</p>
    <section aria-label={zh ? "先看答案" : "Quick answer"} className="my-7 border-l-2 border-orange-500 pl-4">
      <p className="text-base leading-7 text-gray-800 dark:text-gray-200">{content.answer}</p>
    </section>
    <SalaryCalculator page={page} />
    <section className="mt-10" aria-labelledby="formula-heading">
      <h2 id="formula-heading" className="text-xl font-semibold">{zh ? "怎么算" : "The calculation"}</h2>
      <p className="mt-3 rounded-lg bg-gray-100 p-4 text-sm leading-7 dark:bg-gray-900">{content.formula}</p>
    </section>
    <section className="mt-10" aria-labelledby="examples-heading">
      <h2 id="examples-heading" className="text-xl font-semibold">{zh ? "公开示例" : "Worked examples"}</h2>
      <p className="mt-2 text-sm leading-6 text-gray-500 dark:text-gray-400">{zh ? "以下是固定示例，使用与上方计算器相同的规则，便于对照不同条件。" : "These fixed examples use the same rules as the calculator above, so you can compare the assumptions."}</p>
      <div className="mt-4 divide-y divide-gray-200 dark:divide-gray-800">
        {examples.map(({ label, state, result }) => <article key={label} className="py-5">
          <h3 className="text-sm font-semibold">{label}</h3>
          {result.ok && <dl className="mt-3 grid gap-x-8 gap-y-2 sm:grid-cols-2">{result.rows.map((row) => <div key={row.label} className="flex flex-wrap justify-between gap-x-3 gap-y-1 text-sm"><dt className="text-gray-500 dark:text-gray-400">{row.label}</dt><dd className="font-medium tabular-nums">{formatMoney(row.value, lang, state.currency)}</dd></div>)}</dl>}
        </article>)}
      </div>
    </section>
    <div className="mt-10 space-y-9">
      {content.sections.map((section) => <section key={section.heading}><h2 className="text-xl font-semibold">{section.heading}</h2><div className="mt-3 space-y-3">{section.paragraphs.map((paragraph) => <p key={paragraph} className="text-sm leading-7 text-gray-600 dark:text-gray-300">{paragraph}</p>)}</div></section>)}
    </div>
    {zh && <section className="mt-10 border-t border-gray-200 pt-6 dark:border-gray-800" aria-labelledby="source-heading">
      <h2 id="source-heading" className="text-base font-semibold">21.75计薪参考：来源与适用范围</h2>
      <p className="mt-3 text-sm leading-7 text-gray-600 dark:text-gray-300">{cnPayReference.appliesTo}。{cnPayReference.exclusions}</p>
      <a href={cnPayReference.sourceUrls[0]} rel="noopener noreferrer" className={`mt-3 inline-block text-sm leading-6 ${linkClass}`}>{cnPayReference.title}（中国政府网）</a>
      <p className="mt-2 text-xs leading-6 text-gray-500 dark:text-gray-400">通知落款：<time dateTime={cnPayReference.noticeDate}>2025年1月1日</time> · 来源核验：<time dateTime={cnPayReference.reviewedAt}>2026年10月31日</time></p>
    </section>}
    <section className="mt-10 border-t border-gray-200 pt-6 dark:border-gray-800">
      <h2 className="text-base font-semibold">{zh ? "继续用其他工具" : "Related tools"}</h2>
      <ul className="mt-3 space-y-3 text-sm">{related.map((item) => <li key={item.id}><Link href={item.path} className={linkClass}>{item.title}</Link></li>)}<li><Link href={`/${lang}/work-hours-calculator`} className={linkClass}>{zh ? "班次工时计算器" : "Work hours calculator"}</Link></li>{directory && <li><Link href={directory.path} className={linkClass}>{zh ? "查看工具库" : "Browse all tools"}</Link></li>}</ul>
    </section>
  </ToolPageFrame>;
}
