import Link from "next/link";
import { notFound } from "next/navigation";
import { getBuildPages, getDirectoryPage, getRelatedPages } from "@/features/web-tools/catalog/pages";
import { toolPageJsonLd, toolPageMetadata } from "@/features/web-tools/catalog/metadata";
import { ToolPageFrame } from "@/features/web-tools/components/ToolPageFrame";

export const dynamicParams = false;
export function generateStaticParams() { return getBuildPages().filter((page) => page.kind === "directory").map((page) => ({ lang: page.lang })); }
export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  const page = getDirectoryPage(lang);
  return page ? toolPageMetadata(page) : { robots: { index: false, follow: false } };
}
export default async function ToolsDirectory({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  const page = getDirectoryPage(lang);
  if (!page) notFound();
  const zh = lang === "zh-CN";
  const tools = getRelatedPages(page);
  const shiftLinks = zh ? [["996", "996工时"], ["9-to-5", "朝九晚五"], ["9-to-6", "朝九晚六"], ["night-shift", "跨午夜夜班"]] : [["996", "996 schedule"], ["9-to-5", "9-to-5 schedule"], ["9-to-6", "9-to-6 schedule"], ["night-shift", "Night shift"]];
  return <ToolPageFrame page={page}>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(toolPageJsonLd(page)).replace(/</g, "\\u003c") }} />
    <p className="mt-4 max-w-3xl text-base leading-7 text-gray-600 dark:text-gray-300">{page.description} {zh ? "计算可直接在网页完成，无需账号。工资输入只保留在当前页面。" : "Complete your calculation on the web without an account. Salary inputs stay in the current page."}</p>
    <section className="mt-10">
      <h2 className="text-xl font-semibold">{zh ? "税前工资换算 · 中国大陆" : "Gross pay conversions · United States"}</h2>
      <p className="mt-3 text-sm leading-7 text-gray-600 dark:text-gray-300">{zh ? "按问题选择工具。21.75计薪参考与实际出勤均摊分开；币种不决定雇佣市场，所有结果均不含税费扣款。" : "Choose the question you want to answer. Adjust paid hours, paid weeks and included bonuses. These are gross-pay estimates, not take-home pay or a dated payroll calendar."}</p>
      <ul className="mt-4 divide-y divide-gray-200 dark:divide-gray-800">{tools.map((tool) => <li key={tool.id} className="py-5"><Link href={tool.path} className="font-semibold text-orange-700 underline-offset-4 hover:underline dark:text-orange-400">{tool.title}</Link><p className="mt-2 text-sm leading-6 text-gray-600 dark:text-gray-400">{tool.description}</p></li>)}</ul>
    </section>
    <section className="mt-10 border-t border-gray-200 pt-7 dark:border-gray-800">
      <h2 className="text-xl font-semibold">{zh ? "班次与休息时间" : "Shifts and breaks"}</h2>
      <p className="mt-3 text-sm leading-7 text-gray-600 dark:text-gray-300">{zh ? "核对上下班跨度、无薪休息和跨午夜班次，再把对应工作量用于收入比较。工时工具不替你判断法定加班或工资合规。" : "Check a shift's span, unpaid breaks and overnight hours before comparing pay. Hours alone do not determine legal overtime or payroll compliance."}</p>
      <Link href={`/${lang}/work-hours-calculator`} className="mt-4 inline-block font-medium text-orange-700 underline underline-offset-4 dark:text-orange-400">{zh ? "打开班次工时计算器" : "Open the work hours calculator"}</Link>
      <ul className="mt-5 flex flex-wrap gap-x-6 gap-y-3 text-sm">{shiftLinks.map(([slug, label]) => <li key={slug}><Link href={`/${lang}/${slug}`} className="text-gray-600 underline underline-offset-4 hover:text-orange-600 dark:text-gray-300">{label}</Link></li>)}</ul>
    </section>
    <section className="mt-10 border-t border-gray-200 pt-7 dark:border-gray-800"><h2 className="text-xl font-semibold">{zh ? "选择计算口径" : "Choose a consistent basis"}</h2><p className="mt-3 text-sm leading-7 text-gray-600 dark:text-gray-300">{zh ? "年化换算适合比较全年收入和发薪周期；实际工作量均摊用于同一期间收入与劳动小时的比较；地区参考只用于标明适用范围的规则。把收入与工时保持在同一期间，避免将计薪日误当成实际上班天数。" : "Annualized conversions compare income across pay periods using a paid schedule. Income per actual hour worked answers a different question. Keep pay and hours in the same period, and distinguish paid leave from actual labor. A market label identifies the page's assumptions; it does not infer your location or employment terms."}</p></section>
  </ToolPageFrame>;
}
