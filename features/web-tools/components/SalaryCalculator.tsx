"use client";

import { useId, useState } from "react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { ToolPage } from "../catalog/pages";
import { calculateDisplay, formatMoney, initialCalculatorState, type CalculatorState } from "../content/calculator";

const controlClass = "mt-1.5 w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5 text-base text-gray-900 focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/20 dark:border-gray-700 dark:bg-gray-900 dark:text-white";

function CalculatorSelect<T extends string>({ label, value, onValueChange, options, help }: {
  label: string;
  value: T;
  onValueChange: (value: T) => void;
  options: { value: T; label: string }[];
  help?: string;
}) {
  const id = useId();
  return <div className="min-w-0 text-sm font-medium text-gray-700 dark:text-gray-200">
    <label htmlFor={id}>{label}</label>
    <Select value={value} onValueChange={onValueChange}>
      <SelectTrigger id={id} aria-describedby={help ? `${id}-help` : undefined} className={`${controlClass} h-auto min-h-11 gap-3 text-left font-normal focus:ring-orange-500/20 focus:ring-offset-0 [&>span]:min-w-0 [&>span]:truncate [&>svg]:shrink-0`}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent className="max-h-[var(--radix-select-content-available-height)] w-[var(--radix-select-trigger-width)] rounded-lg border-gray-200 bg-white text-gray-900 shadow-lg dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 motion-reduce:animate-none" collisionPadding={12}>
        {options.map((option) => <SelectItem key={option.value} value={option.value} className="rounded-md py-2.5 pr-3 text-sm focus:bg-orange-50 focus:text-orange-950 data-[state=checked]:text-orange-700 dark:focus:bg-orange-950/50 dark:focus:text-orange-100 dark:data-[state=checked]:text-orange-300">{option.label}</SelectItem>)}
      </SelectContent>
    </Select>
    {help && <p id={`${id}-help`} className="mt-1.5 text-xs font-normal leading-5 text-gray-500 dark:text-gray-400">{help}</p>}
  </div>;
}

export function SalaryCalculator({ page }: { page: ToolPage }) {
  const zh = page.lang === "zh-CN";
  const [state, setState] = useState(() => initialCalculatorState(page));
  const result = calculateDisplay(state, page.lang);
  function change<K extends keyof CalculatorState>(key: K, value: CalculatorState[K]) {
    setState((previous) => ({ ...previous, [key]: value }));
  }
  function numberField(key: "amount" | "hours" | "weeks" | "days" | "dailyHours" | "months" | "bonus", label: string, help?: string) {
    return <label className="block text-sm font-medium text-gray-700 dark:text-gray-200">
      {label}
      <input type="text" inputMode="decimal" autoComplete="off" spellCheck={false} value={state[key]} onChange={(event) => change(key, event.target.value)} className={controlClass} />
      {help && <span className="mt-1.5 block text-xs font-normal leading-5 text-gray-500 dark:text-gray-400">{help}</span>}
    </label>;
  }
  const amountLabel = state.purpose !== "annualized" ? "税前月薪" : state.incomeKind === "hourly" ? (zh ? "基础时薪" : "Hourly rate") : state.incomeKind === "annual" ? (zh ? "税前年收入" : "Annual gross income") : (zh ? "基础月薪" : "Base monthly salary");

  return <section aria-labelledby="calculator-heading" className="rounded-2xl border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-900/70 sm:p-7">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <h2 id="calculator-heading" className="text-lg font-semibold text-gray-900 dark:text-white">{zh ? "按你的条件计算" : "Calculate with your numbers"}</h2>
      <button type="button" onClick={() => setState(initialCalculatorState(page))} className="text-sm text-gray-500 underline underline-offset-4 hover:text-orange-600 dark:text-gray-400">{zh ? "恢复示例" : "Reset example"}</button>
    </div>
    <p className="mt-2 text-sm leading-6 text-gray-500 dark:text-gray-400">{zh ? "金额只保留在当前页面，不保存、不写入链接。以下均为税前金额。" : "Your amounts stay in this page. They are not saved or added to the link. All amounts are before deductions."}</p>
    <div className="mt-6 grid gap-5 sm:grid-cols-2">
      {zh && <CalculatorSelect label="计算口径" value={state.purpose} onValueChange={(value) => change("purpose", value)} options={[
        { value: "jurisdiction-reference", label: "21.75计薪参考" },
        { value: "worked-time", label: "实际工作量均摊" },
        { value: "annualized", label: "年化与周期换算" },
      ]} />}
      {state.purpose === "annualized" && <CalculatorSelect label={zh ? "输入收入类型" : "Income to convert"} value={state.incomeKind} onValueChange={(incomeKind) => setState((previous) => ({ ...previous, incomeKind, amount: "" }))} options={[
        { value: "hourly", label: zh ? "时薪" : "Hourly rate" },
        { value: "annual", label: zh ? "年收入" : "Annual income" },
        { value: "monthly", label: zh ? "基础月薪" : "Base monthly salary" },
      ]} />}
      {numberField("amount", amountLabel)}
      {state.purpose === "annualized" && <>
        {numberField("hours", zh ? "每周付薪小时" : "Paid hours per week", zh ? "按合同和付薪安排填写，不含无薪休息。" : "Use your paid schedule, excluding unpaid breaks.")}
        {numberField("weeks", zh ? "每年付薪周数" : "Paid weeks per year", zh ? "有薪假期可计入；无薪周不计。" : "Include paid leave; leave unpaid weeks out.")}
        {state.incomeKind === "monthly" && numberField("months", zh ? "一年基础工资相当于几个月" : "Base salary months per year", zh ? "如13薪填13，与发薪次数分开。" : "For 13 salary months, enter 13. This is separate from payment frequency.")}
        {state.incomeKind === "annual" && <label className="flex items-start gap-3 text-sm leading-6 text-gray-600 dark:text-gray-300 sm:col-span-2">
          <input type="checkbox" checked={state.includesBonus} onChange={(event) => change("includesBonus", event.target.checked)} className="mt-1 h-4 w-4 accent-orange-600" />
          {zh ? "输入的年收入已包含本次要计入的奖金及额外薪资" : "The annual amount already includes all bonuses and extra pay I want to count"}
        </label>}
        {(state.incomeKind !== "annual" || !state.includesBonus) && numberField("bonus", zh ? "另外加入的年度现金奖金" : "Additional annual cash bonus", zh ? "只填写尚未计入的部分，避免重复相加。" : "Add only amounts not already included.")}
      </>}
      {state.purpose === "worked-time" && <>
        {numberField("days", "同月实际或预计工作天数")}
        {numberField("dailyHours", "每天实际劳动小时", "扣除全部休息后填写。9:00–18:00、休息1小时，可填8。固定月薪不会因修改此项自动减少。")}
      </>}
      {state.purpose !== "jurisdiction-reference" && <CalculatorSelect label={zh ? "显示币种" : "Display currency"} value={state.currency} onValueChange={(value) => change("currency", value)} options={[
        { value: "CNY", label: `CNY · ${zh ? "人民币" : "Chinese yuan"}` },
        { value: "USD", label: "USD · US dollar" },
      ]} help={zh ? "只改变金额标识，不换汇、不改变市场规则。" : "Changes the currency label only. No exchange-rate conversion or change of market rules."} />}
    </div>
    {state.purpose === "jurisdiction-reference" && <p className="mt-5 rounded-lg bg-gray-50 px-4 py-3 text-sm leading-6 text-gray-600 dark:bg-gray-800 dark:text-gray-300">参考分母固定为每月21.75个计薪日、每天8小时。想按自己的天数和工时计算，请切换到「实际工作量均摊」。</p>}
    <div className="mt-7 border-t border-gray-200 pt-5 dark:border-gray-700" aria-live="polite" aria-atomic="true">
      {result.ok ? <>
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-200">{zh ? "税前换算结果" : "Gross pay equivalents"}</h3>
        <dl className="mt-3 divide-y divide-gray-100 dark:divide-gray-800">
          {result.rows.map((row) => <div key={row.label} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 py-2.5"><dt className="text-sm text-gray-600 dark:text-gray-300">{row.label}</dt><dd className="text-lg font-semibold tabular-nums text-gray-900 dark:text-white">{formatMoney(row.value, page.lang, state.purpose === "jurisdiction-reference" ? "CNY" : state.currency)}</dd></div>)}
        </dl>
        <p className="mt-4 text-xs leading-5 text-gray-500 dark:text-gray-400">{zh ? "最终显示保留两位小数，中间步骤不先舍入。" : "Amounts are rounded to two decimals for display; intermediate values retain full precision."} {state.purpose === "annualized" ? (zh ? "发薪金额为平均参考额，不代表某年实际发薪日历或每张工资单。" : "Payment figures are averages, not a dated payroll calendar or a prediction of each paycheck.") : (zh ? "不计算税费、扣款或法定加班费。" : "Taxes and other deductions are not calculated.")}</p>
      </> : <p role="status" className="text-sm leading-6 text-red-700 dark:text-red-300">{result.message}</p>}
    </div>
    <noscript><p className="mt-4 text-sm leading-6">{zh ? "上方为默认示例。启用JavaScript可修改条件；下方公式、示例和说明仍可直接阅读。" : "The default example is shown above. Enable JavaScript to edit it; formulas, examples and explanations below remain readable."}</p></noscript>
  </section>;
}
