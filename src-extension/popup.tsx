import { useEffect, useState, type FormEvent } from "react";
import { createRoot } from "react-dom/client";
import { createInstance } from "i18next";
import {
  I18nextProvider,
  initReactI18next,
  useTranslation,
} from "react-i18next";
import {
  ArrowLeft,
  Check,
  ChevronRight,
  ExternalLink,
  Info,
  Coffee,
  Coins,
  Settings2,
  ShieldCheck,
} from "lucide-react";
import { RollingText } from "@/components/RollingText";
import { TimeSelector } from "@/components/TimeSelector";
import { PeriodSummary } from "@/components/PeriodSummary";
import { ThemeToggle, type Theme } from "@/components/ThemeToggle";
import { WorkdaySelector } from "@/components/WorkdaySelector";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { siteConfig } from "@/config/site";
import { officialHomeUrl, officialPageUrl } from "@/lib/site-urls";
import {
  buildShiftTimeline,
  calculateTimelinePayRatio,
  calculateTimelineProgress,
  getActiveBreakEndAtMs,
  getDailySalary,
  getPlannedShiftDurationMs,
  getShiftEndAtMs,
  getShiftRemainingMs,
  getShiftStartAtMs,
} from "@/lib/countdown";
import {
  earningsForRatio,
  startOfWeek,
  startOfYear,
  summarize,
} from "@/lib/summary";
import { startSecondTick } from "@/lib/second-tick";
import { applySavedTheme, readStoredTheme } from "@/lib/theme";
import { getTextDirection, languageNames, locales } from "@/i18n-config";
import {
  breakOptions,
  readPreferences,
  resolvePopupShift,
  STORAGE_KEY,
  type Preferences,
} from "./state";
import { loadTranslation } from "./translations";

// One entry for every platform: doneat.app picks the right download. The UTM
// tags name only this surface, never the schedule, salary or the viewer.
function getAppUrl(lang: string) {
  const url = new URL(officialHomeUrl(lang));
  url.searchParams.set("utm_source", "chrome-extension");
  url.searchParams.set("utm_medium", "referral");
  url.searchParams.set("utm_campaign", "get-app");
  return url.href;
}

function clock(ms: number) {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return [
    Math.floor(seconds / 3600),
    Math.floor(seconds / 60) % 60,
    seconds % 60,
  ]
    .map((value) => String(value).padStart(2, "0"))
    .join(":");
}

function Popup({
  initial,
  storageError,
}: {
  initial: Preferences;
  storageError: boolean;
}) {
  const { t, i18n } = useTranslation();
  const [preferences, setPreferences] = useState(initial);
  const [draft, setDraft] = useState<Preferences | null>(null);
  const [settingsBoundary, setSettingsBoundary] =
    useState<HTMLFormElement | null>(null);
  const [now, setNow] = useState(Date.now);
  const [theme, setTheme] = useState<Theme>(readStoredTheme);
  const [error, setError] = useState(storageError ? "extensionSaveError" : "");

  useEffect(() => {
    performance.mark("doneat:ready");
  }, []);

  useEffect(() => {
    if (preferences.running && !draft) {
      setNow(Date.now());
      return startSecondTick(() => setNow(Date.now()));
    }
  }, [preferences.running, draft]);
  useEffect(() => {
    document.documentElement.lang = preferences.lang;
    document.documentElement.dir = getTextDirection(preferences.lang);
    const lang = preferences.lang;
    let current = true;
    void (async () => {
      if (!i18n.hasResourceBundle(lang, "translation"))
        i18n.addResourceBundle(lang, "translation", await loadTranslation(lang));
      if (current) await i18n.changeLanguage(lang);
    })();
    return () => {
      current = false;
    };
  }, [preferences.lang, i18n]);
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => applySavedTheme(media.matches);
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [theme]);

  function save(next: Preferences) {
    try {
      // Synchronous writes finish before Chrome destroys the popup on blur.
      localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      setPreferences(next);
      setError("");
      return true;
    } catch {
      setError("extensionSaveError");
      return false;
    }
  }

  function changeTheme(next: Theme) {
    try {
      localStorage.setItem("theme", next);
      setTheme(next);
      setError("");
    } catch {
      setError("extensionSaveError");
    }
  }

  const resolved = resolvePopupShift(preferences, now);
  const shift =
    resolved?.shift ??
    buildShiftTimeline(
      preferences.startTime,
      preferences.endTime,
      new Date(now),
      breakOptions(preferences),
    );
  const startsAt = getShiftStartAtMs(shift);
  const endsAt = getShiftEndAtMs(shift);
  const before = startsAt > now;
  const ended = endsAt <= now;
  const breakEnd = getActiveBreakEndAtMs(shift, now);
  const progress = resolved ? calculateTimelineProgress(shift, now) : 0;
  const dailySalary = preferences.showSalary
    ? getDailySalary(
        preferences.salaryAmount,
        preferences.salaryType,
        preferences.monthlyWorkingDays,
      )
    : null;
  const earnings = resolved
    ? earningsForRatio(dailySalary, calculateTimelinePayRatio(shift, now))
    : null;
  const summary = {
    asOf: new Date(now),
    workdays: preferences.workdays,
    currentShiftStart: new Date(startsAt),
    currentShiftEnd: new Date(endsAt),
    plannedDailyHours: getPlannedShiftDurationMs(shift) / 3_600_000,
    todayProgress: progress,
    dailySalary,
  };
  const rows = [
    {
      label: t("summaryThisWeek"),
      data: summarize({ ...summary, periodStart: startOfWeek(new Date(now)) }),
    },
    {
      label: t("summaryThisYear"),
      data: summarize({ ...summary, periodStart: startOfYear(new Date(now)) }),
    },
  ];
  const countdownMs = !resolved
    ? 0
    : ended && resolved.next
      ? getShiftStartAtMs(resolved.next) - now
      : before
        ? startsAt - now
        : breakEnd
          ? breakEnd - now
          : getShiftRemainingMs(shift, now);
  const display = resolved ? clock(countdownMs) : t("restDay");
  const title = !resolved
    ? t("offWorkCountdown")
    : ended
      ? resolved.next
        ? t("nextShiftLabelShort")
        : t("offWorkToday")
      : before
        ? t("nextShiftLabelShort")
        : breakEnd
          ? t("lunchInProgress")
          : t("offWorkCountdown");

  function openSettings(section?: "lunch" | "salary") {
    setDraft({ ...preferences });
    setError("");
    if (section)
      requestAnimationFrame(() => {
        document
          .getElementById(`${section}-section`)
          ?.scrollIntoView({ block: "start" });
      });
  }
  function submitSettings(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft) return;
    if (draft.startTime === draft.endTime) {
      setError("sameTimeError");
      return;
    }
    if (save(draft)) setDraft(null);
  }

  const edit = draft ?? preferences;
  const setEdit = (patch: Partial<Preferences>) => {
    if (draft) setDraft({ ...draft, ...patch });
    else save({ ...preferences, ...patch });
  };
  const timeLabels = {
    hourLabel: t("extensionHour"),
    minuteLabel: t("extensionMinute"),
  };
  const scheduleFields = (
    <>
      <div className="grid grid-cols-2 gap-4">
        {(["startTime", "endTime"] as const).map((key) => (
          <TimeSelector
            key={key}
            id={key}
            label={t(key)}
            value={edit[key]}
            onChange={(hour, minute) => setEdit({ [key]: `${hour}:${minute}` })}
            compact
            {...timeLabels}
          />
        ))}
      </div>
      <div className="popup-workdays">
        <WorkdaySelector
          lang={preferences.lang}
          label={t("workdaysLabel")}
          value={edit.workdays}
          onChange={(workdays) => setEdit({ workdays })}
          compact
        />
      </div>
    </>
  );

  return (
    <div className={`popup-shell select-none ${draft ? "popup-settings" : ""}`}>
      <header className="popup-header">
        {draft && (
          <Button
            variant="ghost"
            size="icon"
            className="popup-icon shrink-0"
            onClick={() => {
              setDraft(null);
              setError("");
            }}
            aria-label={t("backToTimer")}
          >
            <ArrowLeft className="h-4 w-4 rtl:rotate-180" />
          </Button>
        )}
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-xl font-semibold leading-none tracking-tight">
            {draft ? t("settings") : "DoneAt"}
          </h1>
          {!draft && (
            <p
              className="mt-1.5 truncate text-xs font-medium text-gray-500 dark:text-gray-400"
              title={t("offWorkCountdown")}
            >
              {t("offWorkCountdown")}
            </p>
          )}
        </div>
        {!draft && (
          <>
            <div className="popup-theme">
              <ThemeToggle theme={theme} onThemeChange={changeTheme} compact />
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="popup-icon shrink-0"
              onClick={() => openSettings()}
              aria-label={t("settings")}
              title={t("settings")}
            >
              <Settings2 className="h-4 w-4" />
            </Button>
          </>
        )}
      </header>

      {draft ? (
        <form
          id="settings"
          ref={setSettingsBoundary}
          className="popup-scroll min-h-0 flex-1 space-y-4 overflow-y-auto px-5 pb-4"
          onSubmit={submitSettings}
        >
          <section id="lunch-section" className="popup-section space-y-3">
            <div className="flex items-center justify-between gap-3">
              <label
                htmlFor="lunch"
                className="flex items-center gap-2 text-sm font-medium"
              >
                <Coffee className="h-4 w-4 text-orange-500" />
                {t("lunchBreak")}
              </label>
              <Switch
                id="lunch"
                checked={draft.lunchEnabled}
                onCheckedChange={(lunchEnabled) => setEdit({ lunchEnabled })}
              />
            </div>
            {draft.lunchEnabled && (
              <>
                <div className="popup-lunch-fields grid grid-cols-2 items-end gap-3">
                  <TimeSelector
                    id="lunch-time"
                    label={t("lunchStartTime")}
                    value={draft.lunchStartTime}
                    onChange={(hour, minute) =>
                      setEdit({ lunchStartTime: `${hour}:${minute}` })
                    }
                    compact
                    menuSide="auto"
                    {...timeLabels}
                  />
                  <label className="space-y-1.5 text-xs text-muted-foreground">
                    <span className="block">
                      {t("lunchDuration")} · {t("minutesUnit")}
                    </span>
                    <input
                      className="popup-field"
                      type="number"
                      min="1"
                      max="1439"
                      step="1"
                      required
                      defaultValue={draft.lunchDurationMinutes}
                      onChange={(event) => {
                        if (event.target.validity.valid)
                          setEdit({
                            lunchDurationMinutes: event.target.valueAsNumber,
                          });
                      }}
                    />
                  </label>
                </div>
                <p className="text-xs leading-relaxed text-muted-foreground">
                  {t(
                    buildShiftTimeline(
                      draft.startTime,
                      draft.endTime,
                      new Date(now),
                      breakOptions(draft),
                    ).segments.length === 2
                      ? "lunchPauseNote"
                      : "lunchOutsideShift",
                  )}
                </p>
              </>
            )}
          </section>
          <section id="salary-section" className="popup-section space-y-3">
            <div className="flex items-center justify-between gap-3">
              <label
                htmlFor="salary"
                className="flex items-center gap-2 text-sm font-medium"
              >
                <Coins className="h-4 w-4 text-orange-500" />
                {t("salarySettings")}
              </label>
              <Switch
                id="salary"
                checked={draft.showSalary}
                onCheckedChange={(showSalary) => setEdit({ showSalary })}
              />
            </div>
            {draft.showSalary && (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <label className="space-y-1.5 text-xs text-muted-foreground">
                    <span className="block">{t("salaryType")}</span>
                    <Select
                      value={draft.salaryType}
                      onValueChange={(value: Preferences["salaryType"]) =>
                        setEdit({ salaryType: value })
                      }
                    >
                      <SelectTrigger
                        className="popup-field"
                        aria-label={t("salaryType")}
                      >
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent
                        className="popup-select"
                        collisionBoundary={settingsBoundary}
                        collisionPadding={8}
                      >
                        <SelectItem value="monthly">{t("monthly")}</SelectItem>
                        <SelectItem value="daily">{t("daily")}</SelectItem>
                      </SelectContent>
                    </Select>
                  </label>
                  <label className="space-y-1.5 text-xs text-muted-foreground">
                    <span className="block">{t("amount")}</span>
                    <input
                      className={`popup-field ${draft.hideEarnings ? "masked" : ""}`}
                      type="number"
                      min="0"
                      max="999999999999"
                      step="0.01"
                      defaultValue={draft.salaryAmount}
                      onChange={(event) => {
                        if (event.target.validity.valid)
                          setEdit({ salaryAmount: event.target.value });
                      }}
                    />
                  </label>
                </div>
                {draft.salaryType === "monthly" && (
                  <label className="block space-y-1.5 text-xs text-muted-foreground">
                    <span className="block">{t("monthlyWorkingDays")}</span>
                    <input
                      className="popup-field"
                      type="number"
                      min="0.01"
                      max="31"
                      step="0.01"
                      required
                      defaultValue={draft.monthlyWorkingDays}
                      onChange={(event) => {
                        if (event.target.validity.valid)
                          setEdit({
                            monthlyWorkingDays: event.target.valueAsNumber,
                          });
                      }}
                    />
                  </label>
                )}
                <div className="flex items-center justify-between gap-3">
                  <label
                    htmlFor="hide-earnings"
                    className="text-xs text-muted-foreground"
                  >
                    {t("hideEarnings")}
                  </label>
                  <Switch
                    id="hide-earnings"
                    checked={draft.hideEarnings}
                    onCheckedChange={(hideEarnings) =>
                      setEdit({ hideEarnings })
                    }
                  />
                </div>
              </>
            )}
          </section>
          <section className="popup-section space-y-3">
            <label className="block space-y-1.5 text-xs text-muted-foreground">
              <span className="block">{t("chooselanguage")}</span>
              <Select
                value={draft.lang}
                onValueChange={(value: Preferences["lang"]) =>
                  setEdit({ lang: value })
                }
              >
                <SelectTrigger
                  className="popup-field"
                  aria-label={t("chooselanguage")}
                >
                  <SelectValue />
                </SelectTrigger>
                <SelectContent
                  className="popup-select"
                  collisionBoundary={settingsBoundary}
                  collisionPadding={8}
                >
                  {locales.map((lang) => (
                    <SelectItem key={lang} value={lang}>
                      {languageNames[lang]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </label>
            <p className="flex items-start gap-2 text-xs leading-relaxed text-muted-foreground">
              <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0" />
              {t("landingFeature3Body")}
            </p>
          </section>
          <section className="popup-section" aria-labelledby="get-app-title">
            <div className="popup-get-app">
              <div className="flex items-center gap-3">
                {/* The 128 icon keeps Chrome's 16 px transparent padding; the
                    negative margin shows its 96 px artwork at 32 px. */}
                <img
                  src="icons/128.png"
                  alt=""
                  width={43}
                  height={43}
                  className="-m-[5.5px] shrink-0"
                />
                <div className="min-w-0 flex-1">
                  <strong
                    id="get-app-title"
                    className="block truncate text-[13px] font-semibold"
                  >
                    {siteConfig.brandName}
                  </strong>
                  <span className="mt-0.5 block truncate text-[11px] text-muted-foreground">
                    {t("getAppPlatforms")}
                  </span>
                </div>
              </div>
              <p className="mt-3 space-y-1 text-[11px] leading-relaxed text-muted-foreground">
                <span className="block">{t("getAppNoteDesktop")}</span>
                <span className="block">{t("getAppNoteMobile")}</span>
              </p>
              <a
                href={getAppUrl(preferences.lang)}
                target="_blank"
                rel="noopener noreferrer"
                className="popup-get-app-link"
              >
                {t("getApp")}
                <ExternalLink className="h-3.5 w-3.5" />
              </a>
            </div>
            <a
              href={officialPageUrl(preferences.lang, "about")}
              target="_blank"
              rel="noopener noreferrer"
              className="popup-about"
            >
              <Info className="h-3.5 w-3.5" />
              <span className="flex-1">{t("aboutProject")}</span>
              <ExternalLink className="h-3 w-3" />
            </a>
          </section>
        </form>
      ) : (
        <main className="popup-scroll min-h-0 flex-1 overflow-y-auto px-5 pb-4">
          <div className="flex flex-col gap-4">
            {!preferences.running ? (
              <>
                <section className="space-y-3">{scheduleFields}</section>
                <div className="grid grid-cols-2 gap-2">
                  {[
                    {
                      icon: Coffee,
                      key: "lunchBreak",
                      section: "lunch" as const,
                      active: preferences.lunchEnabled,
                    },
                    {
                      icon: Coins,
                      key: "salarySettings",
                      section: "salary" as const,
                      active: preferences.showSalary,
                    },
                  ].map(({ icon: Icon, key, section, active }) => (
                    <button
                      key={key}
                      type="button"
                      className="popup-quick"
                      onClick={() => openSettings(section)}
                    >
                      <Icon
                        className={`h-3.5 w-3.5 shrink-0 ${active ? "text-orange-500" : "text-muted-foreground"}`}
                      />
                      <span className="min-w-0 flex-1 truncate">{t(key)}</span>
                      <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground rtl:rotate-180" />
                    </button>
                  ))}
                </div>
                {!resolved && (
                  <p className="text-center text-sm text-muted-foreground">
                    {t("restDay")}
                  </p>
                )}
              </>
            ) : (
              <>
                <section className="popup-countdown">
                  <p className="text-xs text-muted-foreground">{title}</p>
                  <div
                    dir={resolved ? "ltr" : undefined}
                    role="timer"
                    className={
                      resolved ? "popup-digits" : "my-3 text-3xl font-semibold"
                    }
                  >
                    <RollingText text={display} />
                  </div>
                  <div className="mb-2 flex items-center justify-between text-[11px] text-muted-foreground">
                    <span>{ended ? t("offWorkToday") : t("progress")}</span>
                    <span className="tabular-nums">
                      {Math.round(progress)}%
                    </span>
                  </div>
                  <div
                    className="popup-progress"
                    dir="ltr"
                    role="progressbar"
                    aria-label={t("offWorkCountdown")}
                    aria-valuemin={0}
                    aria-valuemax={100}
                    aria-valuenow={Math.round(progress)}
                  >
                    <div style={{ width: `${progress}%` }} />
                  </div>
                </section>
                <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
                  <span>
                    {t("startTime")}{" "}
                    <b dir="ltr" className="font-medium text-foreground">
                      {preferences.startTime}
                    </b>
                  </span>
                  <span>
                    {t("endTime")}{" "}
                    <b dir="ltr" className="font-medium text-foreground">
                      {preferences.endTime}
                    </b>
                  </span>
                </div>
              </>
            )}
            <div className="popup-summary">
              <PeriodSummary
                lang={preferences.lang}
                note={t("summaryEstimateNote")}
                rows={rows}
                hideEarnings={preferences.hideEarnings}
                compact
                currentEarnings={
                  earnings === null
                    ? undefined
                    : {
                        label: t("moneyEarned"),
                        value: new Intl.NumberFormat(preferences.lang, {
                          minimumFractionDigits: 2,
                          maximumFractionDigits: 2,
                        }).format(earnings),
                        showLabel: t("showEarnings"),
                        hideLabel: t("hideEarnings"),
                        onToggle: () =>
                          save({
                            ...preferences,
                            hideEarnings: !preferences.hideEarnings,
                          }),
                      }
                }
              />
            </div>
          </div>
        </main>
      )}
      {error && (
        <p
          role="alert"
          className="px-5 pb-3 text-xs text-red-600 dark:text-red-400"
        >
          {t(error)}
        </p>
      )}
      <footer className="popup-footer">
        {draft ? (
          <Button
            type="submit"
            form="settings"
            className="popup-primary h-9 w-full gap-2 rounded-lg"
          >
            <Check className="h-4 w-4" />
            {t("extensionSave")}
          </Button>
        ) : (
          <Button
            variant={preferences.running ? "outline" : "default"}
            className={`h-9 w-full rounded-lg px-4 ${preferences.running ? "popup-edit" : "popup-primary"}`}
            onClick={() => {
              if (
                !preferences.running &&
                preferences.startTime === preferences.endTime
              ) {
                setError("sameTimeError");
                return;
              }
              save({ ...preferences, running: !preferences.running });
              setNow(Date.now());
            }}
          >
            {preferences.running ? (
              <>
                <ArrowLeft className="me-2 h-4 w-4 rtl:rotate-180" />
                {t("extensionEditSchedule")}
              </>
            ) : (
              t("startCountdown")
            )}
          </Button>
        )}
      </footer>
    </div>
  );
}

let raw: string | null = null;
let storageError = false;
try {
  raw = localStorage.getItem(STORAGE_KEY);
} catch {
  storageError = true;
}
const initial = readPreferences(raw, navigator.language);
document.documentElement.lang = initial.lang;
document.documentElement.dir = getTextDirection(initial.lang);
applySavedTheme(matchMedia("(prefers-color-scheme: dark)").matches);
const i18n = createInstance();
void i18n.use(initReactI18next).init({
  resources: {
    [initial.lang]: { translation: await loadTranslation(initial.lang) },
  },
  lng: initial.lang,
  initImmediate: false,
  interpolation: { escapeValue: false },
});
createRoot(document.getElementById("root")!).render(
  <I18nextProvider i18n={i18n}>
    <Popup initial={initial} storageError={storageError} />
  </I18nextProvider>,
);
