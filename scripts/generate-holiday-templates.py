#!/usr/bin/env python3
"""Build the offline holiday template bundle from pinned local sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import zipfile
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "scripts/holiday-template-sources.json"
OUTPUT_PATH = ROOT / "src-mobile/ios/Shared/Resources/HolidayTemplates.json"
YEARS = range(2020, 2036)
CN_YEARS = range(2007, 2028)
LANGUAGES = {
    "ar": "ar",
    "de": "de",
    "en": "en_US",
    "es": "es",
    "fr": "fr",
    "hi-IN": "hi",
    "id": "id",
    "it": "it",
    "ja": "ja",
    "ko": "ko",
    "mr-IN": "mr",
    "pt": "pt",
    "ru": "ru",
    "th": "th",
    "tr": "tr",
    "vi": "vi",
    "zh-CN": "zh_CN",
    "zh-HK": "zh_HK",
    "zh-TW": "zh_TW",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def holiday_cn_hash(source: Path) -> str:
    digest = hashlib.sha256()
    for year in CN_YEARS:
        path = source / f"{year}.json"
        digest.update(path.name.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def translated_names(holidays, code: str, dates: set, default_language: str) -> dict:
    supported = set(holidays.country_holidays(code).supported_languages)
    fallback_language = "en_US" if "en_US" in supported else default_language
    by_language = {}
    for app_language, source_language in LANGUAGES.items():
        # Some sources only expose a regional locale (for example pt_BR/pt_PT).
        # Keep the country's native variant when the app requests that language.
        native_language = (
            default_language
            if default_language and default_language.split("_")[0] == source_language
            else fallback_language
        )
        language = source_language if source_language in supported else native_language
        calendar = holidays.country_holidays(code, years=YEARS, language=language)
        by_language[app_language] = {day: calendar.get(day) for day in dates}
    return by_language


def load_global_regions(holidays) -> dict[str, list[tuple[int, int, dict[str, str]]]]:
    from holidays.registry import COUNTRIES

    regions = {}
    for aliases in COUNTRIES.values():
        code = aliases[1]
        calendar = holidays.country_holidays(code, years=YEARS)
        public = dict(calendar.items())
        dates = set(public)
        translations = translated_names(holidays, code, dates, calendar.default_language)
        rows = []
        for day in sorted(dates):
            names = {
                language: (values.get(day) or public[day])
                for language, values in translations.items()
            }
            rows.append((int(day.strftime("%Y%m%d")), 0, names))
        regions[code] = rows
    return regions


def load_predictions(lock: dict) -> dict:
    predictions = {}
    for entry in lock.get("chinaPredictions", []):
        path = ROOT / entry["path"]
        if sha256(path) != entry["sha256"]:
            raise ValueError(f"China prediction {path} does not match source lock")
        payload = json.loads(path.read_text())
        year = entry["year"]
        if (payload.get("year") != year or payload.get("version") != entry["version"]
                or payload.get("status") != "user-approved-prediction"
                or entry.get("status") != payload["status"] or not payload.get("days")):
            raise ValueError(f"China prediction {year} metadata is invalid")
        if year in predictions:
            raise ValueError(f"duplicate China prediction for {year}")
        predictions[year] = payload
    return predictions


def load_china(source: Path, predictions: dict | None = None) -> tuple[list, list[int]]:
    """Official announcements take precedence over pinned local estimates.

    Sources are reviewed and hash-locked by the caller; this never fetches data
    or changes a selected year based on the current date.
    """
    predictions = predictions or {}
    rows = []
    estimated_years = []
    for year in CN_YEARS:
        payload = json.loads((source / f"{year}.json").read_text())
        if not payload["papers"] and not payload["days"]:
            if year not in predictions:
                continue
            payload = predictions[year]
            estimated_years.append(year)
        elif not payload["papers"] or not payload["days"]:
            raise ValueError(f"China {year} has incomplete announcement data")
        for day in payload["days"]:
            civil_date = date.fromisoformat(day["date"])
            if year in estimated_years and civil_date.year != year:
                raise ValueError(f"China {year} prediction has a date outside its source year")
            # New Year notices can include the preceding December. Retain the
            # existing covered-window policy without inventing an extra year.
            if civil_date.year < min(CN_YEARS) or civil_date.year > max(CN_YEARS):
                continue
            if type(day["isOffDay"]) is not bool or not day["name"]:
                raise ValueError(f"China {year} has an invalid day")
            date_value = int(civil_date.strftime("%Y%m%d"))
            source_name = day["name"]
            rows.append((
                date_value,
                0 if day["isOffDay"] else 1,
                {language: source_name for language in LANGUAGES},
            ))
    return sorted(rows), estimated_years


def compact(regions, dataset_version: str, estimated_years: dict | None = None,
            base_dataset_version: str | None = None) -> dict:
    names = []
    name_indexes = {}
    output_regions = {}
    for code, rows in sorted(regions.items()):
        compact_rows = []
        seen_dates = set()
        for date, workday, translations in rows:
            if date in seen_dates:
                raise ValueError(f"duplicate date {date} in {code}")
            seen_dates.add(date)
            key = tuple(translations[language] for language in LANGUAGES)
            if key not in name_indexes:
                name_indexes[key] = len(names)
                names.append(dict(zip(LANGUAGES, key)))
            compact_rows.append([date, workday, name_indexes[key]])
        years = [date // 10000 for date in seen_dates]
        output_regions[code] = {
            "coveredFromYear": min(years) if code == "CN" else 2020,
            "coveredThroughYear": max(years) if code == "CN" else 2035,
            "days": compact_rows,
        }
        if estimated_years and estimated_years.get(code):
            output_regions[code]["estimatedYears"] = sorted(estimated_years[code])
        if code == "CN" and set(years) != set(range(min(years), max(years) + 1)):
            raise ValueError("China coverage contains an unavailable year")
        if code != "CN" and years and (min(years) < 2020 or max(years) > 2035):
            raise ValueError(f"{code} produced a date outside 2020-2035")
    payload = {
        "schemaVersion": 1,
        "datasetVersion": dataset_version,
        "names": names,
        "regions": output_regions,
    }
    # Retain the unchanged upstream revision on exported non-China calendars.
    # The bundle/index revision identifies the combined official + local inputs.
    if base_dataset_version:
        payload["baseDatasetVersion"] = base_dataset_version
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--holidays-wheel", type=Path, required=True)
    parser.add_argument("--holiday-cn", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    args = parser.parse_args()
    lock = json.loads(LOCK_PATH.read_text())
    if sha256(args.holidays_wheel) != lock["vacanzaHolidays"]["sha256"]:
        raise ValueError("vacanza/holidays wheel does not match source lock")
    if holiday_cn_hash(args.holiday_cn) != lock["holidayCn"]["dataSha256"]:
        raise ValueError("holiday-cn inputs do not match source lock")
    predictions = load_predictions(lock)

    with tempfile.TemporaryDirectory() as package_directory:
        with zipfile.ZipFile(args.holidays_wheel) as wheel:
            wheel.extractall(package_directory)
        sys.path.insert(0, package_directory)
        import holidays

        if holidays.__version__ != lock["vacanzaHolidays"]["version"]:
            raise ValueError("vacanza/holidays package version does not match source lock")
        regions = load_global_regions(holidays)
        regions["CN"], estimated_years = load_china(args.holiday_cn, predictions)
        payload = compact(regions, lock["datasetVersion"], {"CN": estimated_years},
                          lock.get("baseDatasetVersion"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Wrote {len(payload['regions'])} regions and {len(payload['names'])} names to {args.output}")


if __name__ == "__main__":
    main()
