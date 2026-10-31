import type { ToolPage } from "../catalog/pages";
import { calculateDisplay, formatMoney, initialCalculatorState, type CalculatorState } from "./calculator";

export interface ContentSection { heading: string; paragraphs: string[]; }
export interface PublicExample { label: string; state: CalculatorState; }
export interface SalaryContent { intro: string; answer: string; formula: string; sections: ContentSection[]; examples: PublicExample[]; }

/** Only edited, public example amounts belong here; never visitor input. */
export function getSalaryContent(page: ToolPage): SalaryContent {
  const initial = initialCalculatorState(page);
  const example = (label: string, overrides: Partial<CalculatorState> = {}): PublicExample => ({ label, state: { ...initial, ...overrides } });
  const money = (overrides: Partial<CalculatorState>, row = 0): string => {
    const state = { ...initial, ...overrides };
    const result = calculateDisplay(state, page.lang);
    if (!result.ok || !result.rows[row]) throw new Error(`Invalid public example: ${page.id}`);
    return formatMoney(result.rows[row].value, page.lang, state.currency);
  };
  const commonCN: ContentSection = { heading: "这三个数字回答不同的问题", paragraphs: [
    "计薪参考回答的是按指定折算规则，一天或一小时对应多少工资。实际工作量均摊回答的是同一个月的收入，平均分到自己实际或预计工作天数、劳动小时后是多少。年化换算则把基础收入、薪资月数和额外奖金合并，再按付薪小时或发薪频率换算。",
    "三种结果不同，并不意味着其中一项算错。先确定要比较的是工资折算参考、这一月的实际投入，还是全年收入，再选择对应分母。所有金额均为税前，不计算社保、公积金、个税或其他扣款。",
  ] };
  const commonUS: ContentSection = { heading: "Gross pay, paid hours and actual work", paragraphs: [
    "Gross pay is the amount before income tax, payroll deductions and benefits deductions. This calculator does not estimate take-home pay, withholding or legal overtime. The currency selector changes the label only; it does not convert money or apply another country's payroll rules.",
    "Paid hours can include paid time off. Actual labor hours exclude breaks and may answer a different question. Use a consistent paid-hours basis here. If your rate or schedule varies, calculate each part separately before comparing the totals; a single average rate does not reproduce a variable payroll.",
  ] };
  switch (page.id) {
    case "cn-overview": return {
      intro: "先选计算口径，再看税前收入的日、小时或全年参考额。月薪、实际工作量和21.75计薪参考各有用途。",
      answer: `同样是月薪10,000元，按21.75计薪日折算约为${money({})}/日、${money({}, 1)}/小时；按实际22天、每天8小时均摊，则约为${money({ purpose: "worked-time" })}/日、${money({ purpose: "worked-time" }, 1)}/小时。`,
      formula: "计薪参考：月薪 ÷ 21.75；实际均摊：同期收入 ÷ 同期工作量；年收入：基础月薪 × 薪资月数 + 未计入的奖金。",
      sections: [commonCN, { heading: "月薪、几薪与月均收入分开看", paragraphs: [
        `基础月薪10,000元、13薪、另加尚未包含的年度现金奖金5,000元，全年计入收入为${money({ purpose: "annualized", months: "13", bonus: "5000" })}，月均为${money({ purpose: "annualized", months: "13", bonus: "5000" }, 1)}。基础月薪仍为10,000元，与月均收入分开显示。`,
        "薪资月数描述一年基础工资的总量；发薪次数描述如何分次支付。这两项不能互相替代。输入年收入总额时，若奖金已经包含在内，就不要再加同一笔奖金。",
      ] }, { heading: "按问题继续计算", paragraphs: [
        "想知道一个月工资摊到一天是多少，可以从月薪换日薪开始；想比较两份工作花费的时间，可看实际工作小时均摊；想弄清工资条为何用21.75，查看计薪日专题和原始通知。",
        "这里只换算你填写的金额，不判断请假一天应扣多少、加班应支付多少或合同是否合规。实际工资条还可能包含不同收入项目和扣款，请结合合同、工资条及适用规定核对。",
      ] }],
      examples: [example("月薪10,000元，21.75计薪参考"), example("同月10,000元，实际22天×8小时", { purpose: "worked-time" }), example("月薪10,000元、13薪、额外奖金5,000元", { purpose: "annualized", months: "13", bonus: "5000" })],
    };
    case "cn-monthly-to-daily": return {
      intro: "一天工资有两种常用看法：按21.75计薪日折算，或把同月收入分到自己实际工作的天数。两种口径可在下方切换。",
      answer: `月薪10,000元按21.75计薪日折算，日工资参考为${money({})}；若这个月实际工作22天，每工作日均摊为${money({ purpose: "worked-time" })}。`,
      formula: "日工资折算参考 = 税前月薪 ÷ 21.75；每实际工作日收入 = 同月税前收入 ÷ 同月工作天数。",
      sections: [{ heading: "什么时候用21.75，什么时候用实际天数", paragraphs: [
        "21.75是工资折算使用的月计薪日数，不代表每个月实际上班21.75天。参考模式采用固定分母，方便查看通知所述的日工资折算。月份长短和当月休息安排不会自动改变这个分母。",
        "想了解这一月的收入与时间投入，可选择实际工作量均摊，填写同月实际或预计工作的天数。如果收入来自整月，天数也应覆盖整月；不要把整月工资除以半个月的出勤天数，再把结果当作完整月份的平均日收入。",
      ] }, { heading: "工作天数改变，均摊额会怎样", paragraphs: [
        "固定月薪不变时，均摊的工作天数越多，每天对应的金额越少。这只是用于比较的平均值，不表示雇主按这个数字逐日发薪，也不表示少工作一天就一定扣除同样金额。",
        "若有半天或不同长度的班次，按天比较可能掩盖差异。可以改用月薪换时薪，把每段劳动时间合计后作比较。这里只支持相同日均小时的简化输入，复杂排班请先确认同月总工作量。",
      ] }, commonCN],
      examples: [example("月薪10,000元，计薪日参考"), example("同月10,000元，工作22天", { purpose: "worked-time" }), example("同月10,000元，工作20天", { purpose: "worked-time", days: "20" })],
    };
    case "cn-monthly-to-hourly": return {
      intro: "把同一个月的税前收入除以实际劳动小时，看看每小时对应多少收入。计薪参考可另选21.75×8小时，两者分开展示。",
      answer: `月收入10,000元、当月工作22天、每天实际劳动8小时，每实际工作小时约${money({}, 1)}。21.75×8的工资折算参考约${money({ purpose: "jurisdiction-reference" }, 1)}/小时。`,
      formula: "实际均摊时薪 = 同期税前收入 ÷（工作天数 × 每天实际劳动小时）；计薪参考 = 月薪 ÷（21.75 × 8）。",
      sections: [{ heading: "先扣清休息，再填每天小时", paragraphs: [
        "9:00到18:00的在岗跨度是9小时；若其间休息1小时，实际劳动时间是8小时。实际工作量模式中的每天小时应扣除全部休息。班次工时计算器可帮助核对起止时间和无薪休息，但其付薪时长与实际劳动时长仍要分清。",
        "带薪休息计入付薪时间，实际劳动时长则不包含休息；无薪休息通常两者都不计。按时薪估算班次报酬与把固定月薪分到劳动小时，是不同的问题。这里只对固定月薪做均摊，修改休息或工时不会自动减少月薪。",
      ] }, { heading: "比较工时安排，要保持同一期间", paragraphs: [
        `月收入10,000元、22天、每天8小时与每天9小时，分别约为${money({}, 1)}和${money({ dailyHours: "9" }, 1)}/小时。金额相同、劳动时间不同，就会出现不同的均摊结果。比较月薪时，也可把工作量列在旁边一起看。`,
        "本页不把通勤默认计入劳动小时，也不把超出8小时的部分自动当成法定加班。实际加班认定和报酬需要另行核对，不能从平均时薪直接推出。",
      ] }, commonCN],
      examples: [example("10,000元、22天、每天8小时"), example("10,000元、22天、每天9小时", { dailyHours: "9" }), example("10,000元，21.75×8计薪参考", { purpose: "jurisdiction-reference" })],
    };
    case "cn-workdays-21-75": return {
      intro: "21.75是月计薪日数，20.67是月平均制度工作日数，实际出勤又是另一个数字。先分清用途，再决定工资要除以什么。",
      answer: "2025年通知中，月计薪天数仍为21.75天；月平均制度工作日为20.67天。工资折算参考采用月薪÷21.75，小时工资参考再除以8。",
      formula: "月计薪日数 =（365 − 104）÷ 12 = 21.75；月平均制度工作日 =（365 − 104 − 13）÷ 12 ≈ 20.67。",
      sections: [{ heading: "为什么两个分母不一样", paragraphs: [
        "通知区分制度工作时间与工资折算。制度工作时间的计算扣除了全年休息日和13天法定节假日；计薪天数的计算不扣除法定节假日。因此20.67和21.75各自对应不同用途，不能看到数字更新就用一个替换另一个。",
        "本页依据落款为2025年1月1日的通知，给出日工资、小时工资折算参考。参考中的8小时固定展示；如果你想按每天自己的实际小时均摊，请切换实际工作量模式，结果会明确标为实际均摊。",
      ] }, { heading: "实际出勤不能从平均值直接得出", paragraphs: [
        "某个月实际工作几天，取决于当月日期、休息安排、调休和自己的排班。21.75不是考勤表，20.67也不是所有月份统一的实际上班天数。本工具没有把法定节假日或调休表自动套到你的个人日历。",
        `例如月薪21,750元，按21.75折算为每天${money({ amount: "21750" })}、每小时${money({ amount: "21750" }, 1)}；如果同月实际工作22天、每天8小时，均摊为每天${money({ amount: "21750", purpose: "worked-time" })}、每小时${money({ amount: "21750", purpose: "worked-time" }, 1)}。两个结果回答不同问题。`,
      ] }, { heading: "参考的适用范围", paragraphs: [
        "本页只演示该通知所述的工资折算，不提供请假扣薪、法定加班费、税后收入或个案合规结论。需要这些结论时，应结合自己的工资构成、合同和适用规定核对。",
        "原始通知、通知日期和本次来源核验日期见下方。来源核验与页面文案审核分开记录；页面只有完成发布审核才进入公开工具目录和搜索清单。",
      ] }],
      examples: [example("月薪21,750元，21.75×8参考", { amount: "21750" }), example("同月21,750元，实际22天×8小时", { amount: "21750", purpose: "worked-time" })],
    };
    case "us-hourly-to-annual": return {
      intro: "Turn an hourly rate into a yearly gross-pay estimate using your paid hours and weeks. Adjust the schedule instead of assuming every job uses 40 hours and 52 weeks.",
      answer: `$25 an hour × 40 paid hours a week × 52 paid weeks is ${money({})} a year, or an average ${money({}, 1)} a month, before deductions. With 50 paid weeks, the annual total is ${money({ weeks: "50" })}.`,
      formula: "Annual gross income = hourly rate × paid hours per week × paid weeks per year + additional annual cash bonus.",
      sections: [{ heading: "Choose paid weeks, including paid leave", paragraphs: [
        "A 52-week estimate assumes the entered paid hours are covered throughout the reference year. Paid vacation can be included in those weeks; unpaid time off should be left out. A seasonal or part-year job may need fewer paid weeks even if its hourly rate is unchanged.",
        "For example, reducing 52 paid weeks to 50 removes two weeks of pay from the annual estimate. It does not change the hourly rate. The monthly result is annual income divided by 12, so it is an average rather than the amount paid in each calendar month.",
      ] }, { heading: "Keep bonuses separate from the base rate", paragraphs: [
        "Use the additional bonus field only for cash pay not already represented by the entered rate and schedule. A $2,000 bonus adds $2,000 to annual income; it is not multiplied by paid weeks. The resulting hourly equivalent includes that bonus spread over paid hours, so it may exceed the base rate you entered.",
        "This estimate applies one straight rate to all entered paid hours. It does not decide whether any hours qualify for an overtime premium. If you need to compare the paycheck schedule, use the biweekly page to see the difference between every two weeks and twice a month.",
      ] }, commonUS],
      examples: [example("$25/hour · 40 hours/week · 52 paid weeks"), example("$25/hour · 40 hours/week · 50 paid weeks", { weeks: "50" }), example("$25/hour · 20 hours/week · 52 paid weeks", { hours: "20" })],
    };
    case "us-annual-to-hourly": return {
      intro: "See what an annual gross salary works out to per paid hour. Enter the hours and weeks behind the salary, and make clear whether bonuses are already included.",
      answer: `A $52,000 annual gross salary divided by 40 paid hours a week and 52 paid weeks equals ${money({}, 2)} per paid hour. At 35 paid hours a week, the same salary is about ${money({ hours: "35" }, 2)} per paid hour.`,
      formula: "Hourly equivalent = annual gross income included in the calculation ÷ (paid hours per week × paid weeks per year).",
      sections: [{ heading: "The 2,080-hour assumption is a choice", paragraphs: [
        "Forty paid hours multiplied by 52 paid weeks gives 2,080 reference hours. That is a convenient model, not a universal measure of how much every salaried employee works. A different paid schedule changes the denominator and the hourly equivalent.",
        "Keep salary and hours aligned. If the salary covers a full paid year including leave, removing paid leave from the denominator changes the question toward income per actual hour worked. It should not be silently mixed into a paid-hour comparison.",
      ] }, { heading: "An hourly equivalent is not a contract rate", paragraphs: [
        "The result helps compare offers or understand a salary. It does not establish a contractual hourly wage, overtime eligibility or an overtime premium. Actual schedules, salary terms and other compensation can affect a comparison beyond this arithmetic.",
        "The annual-income input starts with the assumption that it already includes all cash bonuses and extra pay you want to count. If it does not, clear that checkbox and enter only the additional annual bonus. This prevents the same bonus from being included twice.",
      ] }, commonUS],
      examples: [example("$52,000/year · 40 hours/week · 52 paid weeks"), example("$52,000/year · 35 hours/week · 52 paid weeks", { hours: "35" }), example("$52,000 base + $2,000 additional bonus", { includesBonus: false, bonus: "2000" })],
    };
    case "us-biweekly-paycheck": return {
      intro: "Estimate average gross pay every two weeks, then compare it with twice-monthly pay. Use your annual income or convert an hourly rate first.",
      answer: `$52,000 a year divided into 26 biweekly payments is ${money({}, 4)} per payment before deductions. Dividing it into 24 semimonthly payments gives ${money({}, 5)} per payment.`,
      formula: "Average biweekly gross pay = annual gross income ÷ 26; average semimonthly gross pay = annual gross income ÷ 24.",
      sections: [{ heading: "Every two weeks is different from twice a month", paragraphs: [
        "Biweekly means one payment every two weeks. Semimonthly means two payments each month. The annual reference counts here are 26 and 24 respectively. The larger semimonthly payment in the example does not mean higher annual income; the same total is divided into fewer payments.",
        "The monthly figure is annual income divided by 12. It is not simply two biweekly payments, because biweekly pay dates do not stay aligned with month boundaries. A monthly budget may need the employer's actual pay-date calendar.",
      ] }, { heading: "A reference average, not a payroll calendar", paragraphs: [
        "This page uses 26 reference payments. It does not count pay dates for a specific year, and it does not assert that every real payroll year has exactly 26 paychecks. That requires the first pay date and the employer's payment schedule.",
        "Annual bonuses entered here are spread across the reference payments for comparison. If a bonus is paid separately, your regular paycheck will not match that average. Taxes, benefits, unpaid time and changing hours also affect the amount on an actual pay statement.",
      ] }, commonUS],
      examples: [example("$52,000 annual income · 26 vs 24 reference payments"), example("$25/hour · 40 hours/week · 50 paid weeks", { incomeKind: "hourly", amount: "25", weeks: "50" })],
    };
    default: return {
      intro: "Compare hourly, annual and monthly gross income in one place. Set your paid schedule and income structure to see reference amounts across common pay periods.",
      answer: `At $25 an hour, 40 paid hours a week and 52 paid weeks, annual gross income is ${money({})}. That is ${money({}, 1)} per average month, ${money({}, 4)} per biweekly reference payment or ${money({}, 5)} per semimonthly reference payment.`,
      formula: "Hourly input: annual income = rate × paid hours × paid weeks + extra bonus. Monthly input: annual income = base monthly salary × salary months + extra bonus.",
      sections: [{ heading: "Start with the amount you actually know", paragraphs: [
        "Choose hourly rate, annual income or base monthly salary. The calculator keeps income structure separate from payment frequency. A contract with 13 salary months describes the annual base amount; 26 biweekly payments describes how a yearly total is divided. They are different inputs.",
        "For annual income, say whether all bonuses and extra cash pay are already included. For monthly or hourly income, add only bonus amounts that are not already represented. Equity, employer benefits and non-cash compensation are outside this simple cash-pay comparison.",
      ] }, { heading: "Read averages alongside their assumptions", paragraphs: [
        "Annualized income uses the paid hours and weeks you enter. A monthly average divides the total by 12. Weekly, biweekly and semimonthly reference amounts divide it by 52, 26 and 24. These averages make periods comparable, but they do not generate a dated payroll schedule.",
        "Use the focused pages below for the question at hand: hourly to annual for work schedules and unpaid weeks, annual to hourly for a salary's hourly equivalent, or biweekly pay for the distinction between every two weeks and twice monthly.",
      ] }, commonUS],
      examples: [example("$25/hour · 40 hours/week · 52 paid weeks"), example("$5,000/month · 13 salary months + $2,000 bonus", { incomeKind: "monthly", amount: "5000", months: "13", bonus: "2000" }), example("$52,000 annual income, bonuses already included", { incomeKind: "annual", amount: "52000" })],
    };
  }
}

export function getPublicExampleResults(page: ToolPage) {
  return getSalaryContent(page).examples.map((example) => ({ ...example, result: calculateDisplay(example.state, page.lang) }));
}
