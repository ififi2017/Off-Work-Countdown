#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const dataBytes = await readFile(new URL("src-mobile/ios/Shared/Resources/HolidayTemplates.json", root));
const data = JSON.parse(dataBytes);
const lock = JSON.parse(await readFile(new URL("scripts/holiday-template-sources.json", root), "utf8"));
const attributions = JSON.parse(await readFile(new URL("src-mobile/ios/Shared/Resources/HolidayTemplateAttributions.json", root), "utf8"));
const licenseFiles = [
  ["THIRD_PARTY_LICENSES/vacanza-holidays.txt", lock.vacanzaHolidays.licenseSha256],
  ["THIRD_PARTY_LICENSES/holiday-cn.txt", lock.holidayCn.licenseSha256],
];
const locales = ["ar", "de", "en", "es", "fr", "hi-IN", "id", "it", "ja", "ko", "mr-IN", "pt", "ru", "th", "tr", "vi", "zh-CN", "zh-HK", "zh-TW"];

const fail = (message) => { throw new Error(`Holiday template check failed: ${message}`); };
const predictions = new Map();
for (const entry of lock.chinaPredictions ?? []) {
  const bytes = await readFile(new URL(entry.path, root));
  if (createHash("sha256").update(bytes).digest("hex") !== entry.sha256) fail(`${entry.path} differs from its locked prediction source`);
  const prediction = JSON.parse(bytes);
  if (prediction.year !== entry.year || prediction.version !== entry.version || prediction.status !== "user-approved-prediction" || entry.status !== prediction.status) {
    fail(`${entry.path} is not the reviewed prediction`);
  }
  if (predictions.has(entry.year) || !prediction.days?.length) fail("prediction years must be unique and nonempty");
  predictions.set(entry.year, prediction);
}
if (data.schemaVersion !== 1) fail("schemaVersion must be 1");
if (data.datasetVersion !== lock.datasetVersion) fail("datasetVersion differs from source lock");
if (Object.keys(data.regions).length !== 249) fail("expected all 249 national regions from holidays 0.83");
if (dataBytes.length >= 5_000_000) fail("bundle exceeds the 5 MB product limit");
if (attributions.length !== 2 || attributions.some(({ name, sourceURL, license }) => !name || !sourceURL || !license.includes("Permission is hereby granted"))) {
  fail("bundled MIT attributions are missing or incomplete");
}
for (const [index, [path, expectedHash]] of licenseFiles.entries()) {
  const license = await readFile(new URL(path, root));
  const hash = createHash("sha256").update(license).digest("hex");
  if (hash !== expectedHash) fail(`${path} differs from the pinned upstream license`);
  if (`${attributions[index].license}\n` !== license.toString()) fail(`${path} differs from the bundled attribution`);
}

for (const [index, name] of data.names.entries()) {
  if (JSON.stringify(Object.keys(name)) !== JSON.stringify(locales)) fail(`name ${index} has incomplete or unordered locales`);
  if (Object.values(name).some((value) => typeof value !== "string" || !value)) fail(`name ${index} has an empty value`);
}
for (const [code, region] of Object.entries(data.regions)) {
  const years = region.days.map(([date]) => Math.trunc(date / 10000));
  const expectedCoverage = code === "CN" ? [Math.min(...years), Math.max(...years)] : [2020, 2035];
  if (region.coveredFromYear !== expectedCoverage[0] || region.coveredThroughYear !== expectedCoverage[1]) {
    fail(`${code} coverage differs from the pinned source policy`);
  }
  if (code === "CN" && new Set(years).size !== expectedCoverage[1] - expectedCoverage[0] + 1) fail("China coverage includes an unavailable year");
  if (region.estimatedYears !== undefined) {
    if (code !== "CN" || !Array.isArray(region.estimatedYears) || !region.estimatedYears.length ||
        region.estimatedYears.some((year, index) => !Number.isInteger(year) || !years.includes(year) || !predictions.has(year) || (index && year <= region.estimatedYears[index - 1]))) {
      fail(`${code} has invalid estimated year metadata`);
    }
    for (const year of region.estimatedYears) {
      const actual = region.days.filter(([date]) => Math.trunc(date / 10000) === year)
        .map(([date, work, name]) => [date, work, data.names[name]["zh-CN"]]);
      const expected = predictions.get(year).days.map(({ date, isOffDay, name }) => [Number(date.replaceAll("-", "")), isOffDay ? 0 : 1, name]);
      if (JSON.stringify(actual) !== JSON.stringify(expected)) fail(`China ${year} differs from the reviewed prediction`);
    }
  }
  let previous = 0;
  for (const row of region.days) {
    if (!Array.isArray(row) || row.length !== 3 || !Number.isInteger(row[0])) fail(`${code} has an invalid day row`);
    if (row[0] <= previous) fail(`${code} dates are duplicated or unsorted`);
    if (row[1] !== 0 && row[1] !== 1) fail(`${code} has an invalid workday flag`);
    if (!Number.isInteger(row[2]) || row[2] < 0 || row[2] >= data.names.length) fail(`${code} has an invalid name index`);
    const year = Math.trunc(row[0] / 10000);
    const month = Math.trunc(row[0] / 100) % 100;
    const date = row[0] % 100;
    const civil = new Date(Date.UTC(year, month - 1, date));
    if (civil.getUTCFullYear() !== year || civil.getUTCMonth() !== month - 1 || civil.getUTCDate() !== date) fail(`${code} has an invalid civil date`);
    if (year < expectedCoverage[0] || year > expectedCoverage[1]) fail(`${code} has a date outside coverage`);
    previous = row[0];
  }
}
if (!data.regions.CN.days.some((row) => row[1] === 1)) fail("China has no makeup working days");
if (Object.entries(data.regions).some(([code, region]) => code !== "CN" && region.days.some((row) => row[1] === 1))) {
  fail("only China announcements or reviewed predictions may force makeup working days");
}
const day = (code, date) => data.regions[code].days.find((row) => row[0] === date);
if (day("FI", 20250501)?.[1] !== 0) fail("Finland May Day must remain a public rest day");
if (day("FI", 20250511)) fail("Finland Mother's Day WORKDAY observance must not become a forced workday");
if (day("TW", 20250129)?.[1] !== 0) fail("Taiwan Chinese New Year must remain a public rest day");
const digest = createHash("sha256").update(dataBytes).digest("hex");
if (lock.outputSha256 && digest !== lock.outputSha256) fail("bundle differs from the locked generated output");
console.log(`Holiday templates OK: ${Object.keys(data.regions).length} regions, ${data.names.length} names, ${dataBytes.length} bytes, sha256 ${digest}`);
