#!/usr/bin/env node
// Splits the iOS holiday dataset into one file per region for Web/Desktop, so
// the desktop schedule page loads only the calendar the user picked (CN is
// ~18 KB instead of the whole 2.7 MB set). The iOS file stays the source;
// `--check` (run by npm test) fails when public/holidays is out of date.
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = join(root, "src-mobile/ios/Shared/Resources/HolidayTemplates.json");
const attributionsSource = join(root, "src-mobile/ios/Shared/Resources/HolidayTemplateAttributions.json");
const outDir = join(root, "public/holidays");

export function desktopHolidayFiles() {
  const data = JSON.parse(readFileSync(source, "utf8"));
  const attributions = JSON.parse(readFileSync(attributionsSource, "utf8"));
  const files = new Map();
  const regions = {};
  const estimatedYears = {};
  for (const [id, region] of Object.entries(data.regions).sort(([a], [b]) => a.localeCompare(b))) {
    // Each region keeps only the names it uses, renumbered from zero.
    const used = [...new Set(region.days.map(([, , name]) => name))];
    const local = new Map(used.map((name, index) => [name, index]));
    const days = Object.fromEntries(region.days.map(([date, work, name]) => [String(date), [work, local.get(name)]]));
    regions[id] = [region.coveredFromYear, region.coveredThroughYear];
    if (region.estimatedYears?.length) estimatedYears[id] = region.estimatedYears;
    files.set(`${id}.json`, JSON.stringify({
      datasetVersion: id === "CN" ? data.datasetVersion : (data.baseDatasetVersion ?? data.datasetVersion),
      coveredFromYear: region.coveredFromYear,
      coveredThroughYear: region.coveredThroughYear,
      names: used.map((name) => data.names[name]),
      days,
      ...(region.estimatedYears?.length ? { estimatedYears: region.estimatedYears } : {}),
    }) + "\n");
  }
  files.set("index.json", JSON.stringify({ datasetVersion: data.datasetVersion, regions, sources: attributions,
    ...(Object.keys(estimatedYears).length ? { estimatedYears } : {}),
  }) + "\n");
  return files;
}

export function staleDesktopHolidayFiles(files = desktopHolidayFiles()) {
  let existing = [];
  try { existing = readdirSync(outDir); } catch { /* not generated yet */ }
  const stale = [...files].filter(([name, text]) => {
    try { return readFileSync(join(outDir, name), "utf8") !== text; } catch { return true; }
  }).map(([name]) => name);
  return [...stale, ...existing.filter((name) => !files.has(name))];
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
const files = isMain ? desktopHolidayFiles() : null;
if (!isMain) {
  // Imported by lib/holidays.test.ts.
} else if (process.argv.includes("--check")) {
  const stale = staleDesktopHolidayFiles(files);
  if (stale.length) {
    console.error(`public/holidays is out of date (${stale.slice(0, 5).join(", ")}…). Run npm run generate:desktop-holidays.`);
    process.exit(1);
  }
  console.log(`public/holidays matches the iOS holiday dataset (${files.size} files).`);
} else {
  mkdirSync(outDir, { recursive: true });
  const stale = staleDesktopHolidayFiles(files);
  for (const name of stale) {
    if (files.has(name)) writeFileSync(join(outDir, name), files.get(name));
    else rmSync(join(outDir, name), { force: true });
  }
  console.log(`Updated ${stale.length} files in public/holidays (${files.size} total).`);
}
