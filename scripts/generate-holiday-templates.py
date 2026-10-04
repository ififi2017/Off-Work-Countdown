#!/usr/bin/env python3
"""Build the offline holiday template bundle from pinned local sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import zipfile
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


def _english_name(regions: dict, english: str) -> dict[str, str]:
    """Reuse a name row whose every locale is the English label.

    GB's existing vacanza names are untranslated English. Easter Monday and
    Summer Bank Holiday already exist in that form for other countries.
    """
    for rows in regions.values():
        for _date, _work, names in rows:
            if names.get("en") == english and all(value == english for value in names.values()):
                return dict(names)
    return {language: english for language in LANGUAGES}


def _date_code(day) -> int:
    return day.year * 10_000 + day.month * 100 + day.day


def _last_monday_of_august(year: int) -> int:
    from datetime import date, timedelta

    day = date(year, 8, 31)
    return _date_code(day - timedelta(days=day.weekday()))


def overlay_england_and_wales(regions: dict) -> None:
    """Add England and Wales bank holidays that vacanza omits from GB.

    ``country_holidays("GB")`` is only the holidays common to the whole UK
    (New Year's Day, Good Friday, the early-May and spring bank holidays,
    Christmas Day and Boxing Day, plus weekend substitutes and one-off
    days). https://www.gov.uk/bank-holidays.json ``england-and-wales`` also
    includes Easter Monday and the Summer bank holiday.

    Easter Monday is Easter Sunday + 1, which is the bundled Good Friday + 3
    days. The Summer bank holiday is the last Monday in August. Both are
    always Mondays, so they have no weekend substitute. Scotland (2 January,
    St Andrew's Day, first Monday in August) and Northern Ireland
    (St Patrick's Day, 12 July) need their own region codes; this dataset
    only accepts two-letter country codes.
    """
    rows = regions.get("GB")
    if not rows:
        return
    from datetime import datetime, timedelta

    easter_name = _english_name(regions, "Easter Monday")
    summer_name = _english_name(regions, "Summer Bank Holiday")
    by_date = {date: (date, work, names) for date, work, names in rows}
    for date, _work, names in rows:
        if names.get("en") != "Good Friday":
            continue
        monday = datetime.strptime(str(date), "%Y%m%d").date() + timedelta(days=3)
        code = _date_code(monday)
        existing = by_date.get(code)
        if existing and existing[2].get("en") != "Easter Monday":
            raise ValueError(f"GB {code} is {existing[2].get('en')}, not Easter Monday")
        by_date.setdefault(code, (code, 0, easter_name))
    years = {date // 10000 for date, _work, _names in rows}
    for year in sorted(years):
        code = _last_monday_of_august(year)
        existing = by_date.get(code)
        if existing and existing[2].get("en") != "Summer Bank Holiday":
            raise ValueError(f"GB {code} is {existing[2].get('en')}, not Summer Bank Holiday")
        by_date.setdefault(code, (code, 0, summer_name))
    regions["GB"] = [by_date[date] for date in sorted(by_date)]


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


def load_china(source: Path) -> list[tuple[int, int, dict[str, str]]]:
    rows = []
    for year in CN_YEARS:
        payload = json.loads((source / f"{year}.json").read_text())
        if year == 2027:
            if payload["papers"] or payload["days"]:
                raise ValueError("2027 China data is no longer empty; review and update coverage")
            continue
        if not payload["papers"] or not payload["days"]:
            raise ValueError(f"China {year} has no announcement data")
        for day in payload["days"]:
            date_value = int(day["date"].replace("-", ""))
            if not 20070101 <= date_value <= 20261231:
                continue
            source_name = day["name"]
            rows.append((
                date_value,
                0 if day["isOffDay"] else 1,
                {language: source_name for language in LANGUAGES},
            ))
    return sorted(rows)


def compact(regions, dataset_version: str) -> dict:
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
            "coveredFromYear": 2007 if code == "CN" else 2020,
            "coveredThroughYear": 2026 if code == "CN" else 2035,
            "days": compact_rows,
        }
        if code != "CN" and years and (min(years) < 2020 or max(years) > 2035):
            raise ValueError(f"{code} produced a date outside 2020-2035")
    return {
        "schemaVersion": 1,
        "datasetVersion": dataset_version,
        "names": names,
        "regions": output_regions,
    }


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

    with tempfile.TemporaryDirectory() as package_directory:
        with zipfile.ZipFile(args.holidays_wheel) as wheel:
            wheel.extractall(package_directory)
        sys.path.insert(0, package_directory)
        import holidays

        if holidays.__version__ != lock["vacanzaHolidays"]["version"]:
            raise ValueError("vacanza/holidays package version does not match source lock")
        regions = load_global_regions(holidays)
        regions["CN"] = load_china(args.holiday_cn)
        overlay_england_and_wales(regions)
        payload = compact(regions, lock["datasetVersion"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Wrote {len(payload['regions'])} regions and {len(payload['names'])} names to {args.output}")


if __name__ == "__main__":
    main()
