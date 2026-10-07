import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { expect, it } from "vitest";
import { desktopHolidayFiles, staleDesktopHolidayFiles } from "./generate-desktop-holidays.mjs";

const dataset = () => JSON.parse(readFileSync("src-mobile/ios/Shared/Resources/HolidayTemplates.json", "utf8"));
const chinaYear = (data, year) => data.regions.CN.days.filter(([date]) => Math.trunc(date / 10000) === year)
  .map(([date, work, name]) => [date, work, data.names[name]["zh-CN"]]);

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

it("ships exactly the approved 2027 estimate, with five makeup days and no nine-day National Day", () => {
  const data = dataset();
  const range = (first, last, name) => Array.from({ length: last - first + 1 }, (_, offset) => [first + offset, 0, name]);
  const expected = [
    ...range(20270101, 20270103, "元旦"),
    ...range(20270205, 20270213, "春节"),
    ...range(20270403, 20270405, "清明节"),
    ...range(20270501, 20270505, "劳动节"),
    [20270609, 0, "端午节"], [20270915, 0, "中秋节"],
    ...range(20271001, 20271007, "国庆节"),
    [20270131, 1, "春节"], [20270214, 1, "春节"], [20270508, 1, "劳动节"],
    [20270926, 1, "国庆节"], [20271009, 1, "国庆节"],
  ].sort(([a], [b]) => a - b);
  expect(chinaYear(data, 2027)).toEqual(expected);
  expect(expected.filter(([, work]) => work === 1)).toHaveLength(5);
  expect(data.regions.CN).toMatchObject({ coveredFromYear: 2007, coveredThroughYear: 2027, estimatedYears: [2027] });
  expect(Object.values(data.regions).filter((region) => region.estimatedYears)).toHaveLength(1);
});

it("keeps every confirmed 2026 date, workday flag and name unchanged", () => {
  const canonical = JSON.stringify(chinaYear(dataset(), 2026));
  // Canonical rows before introducing the 2027 prediction.
  expect(createHash("sha256").update(canonical).digest("hex")).toBe("5131c0e44359e2f2911147f91cf553178c56bf3f521371533f3f38c9c70bfae3");
});

it("exports estimate metadata and preserves unchanged upstream region revisions", () => {
  const data = dataset();
  const files = desktopHolidayFiles();
  const cn = JSON.parse(files.get("CN.json"));
  const index = JSON.parse(files.get("index.json"));
  expect(cn.estimatedYears).toEqual([2027]);
  expect(index.estimatedYears).toEqual({ CN: [2027] });
  expect(cn.datasetVersion).toBe(data.datasetVersion);
  expect(index.datasetVersion).toBe(data.datasetVersion);
  expect(JSON.parse(files.get("US.json")).datasetVersion).toBe(data.baseDatasetVersion);
  expect(JSON.parse(files.get("US.json"))).not.toHaveProperty("estimatedYears");
  expect(staleDesktopHolidayFiles(files)).toEqual([]);
});

it("uses reviewed official data before predictions and removes estimated metadata automatically", () => {
  const output = execFileSync("python3", ["-c", `
import importlib.util, json, pathlib, tempfile
spec = importlib.util.spec_from_file_location("generator", "scripts/generate-holiday-templates.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
generator.CN_YEARS = range(2027, 2028)
lock = json.loads(pathlib.Path("scripts/holiday-template-sources.json").read_text())
predictions = generator.load_predictions(lock)
with tempfile.TemporaryDirectory() as directory:
    source = pathlib.Path(directory)
    path = source / "2027.json"
    path.write_text(json.dumps({"papers": [], "days": []}))
    rows, estimated = generator.load_china(source, predictions)
    assert len(rows) == 34 and estimated == [2027]
    assert generator.compact({"CN": rows}, "fixture", {"CN": estimated})["regions"]["CN"]["estimatedYears"] == [2027]
    path.write_text(json.dumps({"papers": ["reviewed-official-announcement"], "days": [{"date": "2027-10-01", "name": "国庆节", "isOffDay": True}]}))
    rows, estimated = generator.load_china(source, predictions)
    assert [row[0] for row in rows] == [20271001] and estimated == []
    region = generator.compact({"CN": rows}, "official-fixture", {"CN": estimated})["regions"]["CN"]
    assert "estimatedYears" not in region
    assert region["coveredFromYear"] == 2027 and region["coveredThroughYear"] == 2027
    path.write_text(json.dumps({"papers": [], "days": []}))
    assert generator.load_china(source) == ([], [])
    path.write_text(json.dumps({"papers": ["announcement-without-days"], "days": []}))
    try:
        generator.load_china(source, predictions)
        raise AssertionError("partial official data must not silently use predictions")
    except ValueError:
        pass
print("official precedence and metadata removal verified")
`], { encoding: "utf8" });
  expect(output).toContain("official precedence and metadata removal verified");
});
