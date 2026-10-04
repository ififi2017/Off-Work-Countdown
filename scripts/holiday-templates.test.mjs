import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

it("ships the pinned, complete holiday dataset and licenses without network generation", () => {
  const output = execFileSync(process.execPath, ["scripts/check-holiday-templates.mjs"], { encoding: "utf8" });
  expect(output).toContain("Holiday templates OK: 249 regions");
});

it("shows Brazilian holidays in Portuguese when the source uses a regional locale", () => {
  const dataset = JSON.parse(readFileSync("src-mobile/ios/Shared/Resources/HolidayTemplates.json", "utf8"));
  const independenceDay = dataset.regions.BR.days.find(([date]) => date === 20260907);
  expect(independenceDay[1]).toBe(0);
  expect(dataset.names[independenceDay[2]].pt).toBe("Independência do Brasil");
});

// england-and-wales from https://www.gov.uk/bank-holidays.json, years that
// overlap this dataset (2020–2028). 2019 is published but outside coverage.
const GOV_UK_ENGLAND_AND_WALES = {
  "Easter Monday": [20200413, 20210405, 20220418, 20230410, 20240401, 20250421, 20260406, 20270329, 20280417],
  "Summer bank holiday": [20200831, 20210830, 20220829, 20230828, 20240826, 20250825, 20260831, 20270830, 20280828],
};

function plusDays(date, days) {
  const year = Math.trunc(date / 10000);
  const month = Math.trunc(date / 100) % 100;
  const day = date % 100;
  const next = new Date(Date.UTC(year, month - 1, day + days));
  return next.getUTCFullYear() * 10000 + (next.getUTCMonth() + 1) * 100 + next.getUTCDate();
}

function lastMondayOfAugust(year) {
  const august31 = new Date(Date.UTC(year, 7, 31));
  const backToMonday = (august31.getUTCDay() + 6) % 7;
  return year * 10000 + 800 + (31 - backToMonday);
}

it("adds England and Wales Easter Monday and the August bank holiday to GB", () => {
  const dataset = JSON.parse(readFileSync("src-mobile/ios/Shared/Resources/HolidayTemplates.json", "utf8"));
  const gb = dataset.regions.GB;
  const byDate = new Map(gb.days.map(([date, work, name]) => [date, { work, name: dataset.names[name].en }]));
  const goodFridays = gb.days.filter(([, , name]) => dataset.names[name].en === "Good Friday").map(([date]) => date);

  for (const [govTitle, dates] of Object.entries(GOV_UK_ENGLAND_AND_WALES)) {
    const expectedName = govTitle === "Easter Monday" ? "Easter Monday" : "Summer Bank Holiday";
    for (const date of dates) {
      expect(byDate.get(date), String(date)).toMatchObject({ work: 0, name: expectedName });
    }
  }
  // Easter Monday is Easter Sunday + 1, stored as Good Friday + 3. The
  // Summer bank holiday is the last Monday in August. gov.uk stops at 2028;
  // 2029–2035 follow the same rules.
  expect(goodFridays.map((date) => plusDays(date, 3))).toEqual([
    ...GOV_UK_ENGLAND_AND_WALES["Easter Monday"],
    20290402, 20300422, 20310414, 20320329, 20330418, 20340410, 20350326,
  ]);
  for (const year of [2029, 2030, 2031, 2032, 2033, 2034, 2035]) {
    expect(byDate.get(lastMondayOfAugust(year))?.name).toBe("Summer Bank Holiday");
  }
  expect(byDate.get(20260406)?.name).toBe("Easter Monday");
  expect(byDate.get(20260831)?.name).toBe("Summer Bank Holiday");
  expect(byDate.get(20270329)?.name).toBe("Easter Monday");
  expect(byDate.get(20270830)?.name).toBe("Summer Bank Holiday");
  // One-off England and Wales days already in the vacanza set.
  expect(byDate.get(20220603)?.name).toBe("Platinum Jubilee of Elizabeth II");
  expect(byDate.get(20220919)?.name).toBe("State Funeral of Queen Elizabeth II");
  expect(byDate.get(20230508)?.name).toBe("Coronation of Charles III");
  // Scotland and Northern Ireland are not separate regions.
  expect(dataset.regions["GB-SCT"]).toBeUndefined();
  expect(byDate.has(20260102)).toBe(false);
  expect(byDate.has(20261130)).toBe(false);
  expect(byDate.has(20260317)).toBe(false);
  expect(byDate.has(20260712)).toBe(false);
});
