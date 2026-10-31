import { describe, expect, it } from "vitest";
import { pageRegistry } from "../catalog/pages";
import { calculateDisplay, initialCalculatorState, formatMoney } from "./calculator";
import { getPublicExampleResults, getSalaryContent } from "./salary-pages";

const us = pageRegistry.find((page) => page.id === "us-hourly-to-annual")!;
const cn = pageRegistry.find((page) => page.id === "cn-monthly-to-hourly")!;

describe("salary form calculation contract", () => {
  it("renders every page's public example through the same calculation path", () => {
    for (const page of pageRegistry.filter((item) => item.kind === "salary")) {
      const result = calculateDisplay(initialCalculatorState(page), page.lang);
      expect(result.ok, page.id).toBe(true);
      if (result.ok) expect(result.rows.every((row) => Number.isFinite(row.value))).toBe(true);
      expect(getSalaryContent(page).answer.length).toBeGreaterThan(20);
      for (const example of getPublicExampleResults(page)) {
        expect(example.result.ok, `${page.id}: ${example.label}`).toBe(true);
        expect(example.result).toEqual(calculateDisplay(example.state, page.lang));
      }
    }
  });
  it("accepts localized thousands and preserves full precision", () => {
    const result = calculateDisplay({ ...initialCalculatorState(us), amount: "25" }, "en");
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.rows[0].value).toBe(52000);
    expect(result.rows[1].value).toBe(52000 / 12);
    expect(formatMoney(result.rows[1].value, "en", "USD")).toBe("$4,333.33");
  });
  it("does not count hidden bonuses when annual income already includes them", () => {
    const result = calculateDisplay({ ...initialCalculatorState(us), incomeKind: "annual", amount: "135,000", bonus: "5000", includesBonus: true }, "en");
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.rows[0].value).toBe(135000);
  });
  it("separates actual work from the fixed CN reference and does not use currency as a rate", () => {
    const state = { ...initialCalculatorState(cn), amount: "21,750", days: "22", dailyHours: "8" };
    const actual = calculateDisplay(state, "zh-CN");
    const reference = calculateDisplay({ ...state, purpose: "jurisdiction-reference" }, "zh-CN");
    expect(actual.ok && reference.ok).toBe(true);
    if (actual.ok && reference.ok) {
      expect(actual.rows[1].value).toBe(21750 / 176);
      expect(reference.rows[1].value).toBe(125);
      expect(reference.metadata.purpose).toBe("jurisdiction-reference");
    }
    expect(calculateDisplay({ ...state, currency: "USD" }, "zh-CN")).toEqual(actual);
  });
  it.each(["", "abc", "1,50", "-1", "Infinity"])("shows an error rather than results for %s", (amount) => {
    expect(calculateDisplay({ ...initialCalculatorState(us), amount }, "en").ok).toBe(false);
  });
  it("rejects zero work hours without displaying a misleading zero wage", () => {
    expect(calculateDisplay({ ...initialCalculatorState(cn), dailyHours: "0" }, "zh-CN").ok).toBe(false);
  });
  it("rejects more workdays than can fit in the selected monthly period", () => {
    expect(calculateDisplay({ ...initialCalculatorState(cn), days: "32" }, "zh-CN").ok).toBe(false);
  });
});
