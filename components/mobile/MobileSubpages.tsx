"use client";

import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { BellOff } from "lucide-react";
import {
  getNotificationPermission,
  openDesktopNotificationSettings,
} from "@/lib/notify";
import { desktopLanguageStorageKey, languageNames, locales } from "@/i18n-config";
import { mobileSelectedTabStorageKey } from "@/lib/mobile-navigation";
import {
  approximateDuration,
  formatMinutes,
  formatMoney,
} from "@/lib/mobile/format";
import {
  LIVE_ACTIVITY_LEAD_CHOICES,
  type IosAppState,
  type NotificationMode,
} from "@/lib/mobile/use-ios-app";
import type { Theme } from "@/components/ThemeToggle";
import {
  IosButton,
  IosChoiceSubpage,
  IosGroup,
  IosRow,
  IosSegmented,
  IosSubpage,
  IosSwitch,
  IosSwitchRow,
} from "./ios-kit";
import { IosTimeField } from "./IosTimeField";
import type { SubpageId } from "./subpage-ids";

const LUNCH_DURATIONS = [30, 45, 60, 90, 120];
const MICRO_BREAK_INTERVALS = [30, 45, 50, 60, 90];
const THEMES: Theme[] = ["auto", "light", "dark", "cyberpunk", "sunset"];
const MINUTE_MS = 60 * 1000;

interface SubpageProps {
  page: SubpageId;
  lang: string;
  app: IosAppState;
  onBack: () => void;
  onOpen: (page: SubpageId) => void;
}

export function MobileSubpage(props: SubpageProps) {
  switch (props.page) {
    case "salary":
      return <SalarySubpage {...props} />;
    case "notifications":
      return <NotificationsSubpage {...props} />;
    case "lunch":
      return <LunchSubpage {...props} />;
    case "health":
      return <HealthSubpage {...props} />;
    case "theme":
      return <ThemeSubpage {...props} />;
    case "language":
      return <LanguageSubpage {...props} />;
    case "lunchDuration":
      return <LunchDurationSubpage {...props} />;
    case "microBreakInterval":
      return <MicroBreakIntervalSubpage {...props} />;
    case "liveActivityLead":
      return <LiveActivityLeadSubpage {...props} />;
    default:
      return null;
  }
}

/* ── Salary ────────────────────────────────────────────────────────────── */

function SalarySubpage({ lang, app, onBack }: SubpageProps) {
  const { t } = useTranslation();
  const { settings, update, dailySalary, view, plannedShift } = app;

  // Entering an amount is the only signal the screen needs: an extra "show
  // salary" switch would be a second way to say the same thing.
  const setAmount = (salaryAmount: string) =>
    update({ salaryAmount, showSalary: salaryAmount.trim() !== "" });

  const effectiveHours =
    plannedShift.hours - plannedShift.lunchMinutes / 60;
  const hourlyRate =
    dailySalary !== null && effectiveHours > 0
      ? dailySalary / effectiveHours
      : null;

  return (
    <IosSubpage
      title={t("salarySettings")}
      backLabel={t("settings")}
      onBack={onBack}
    >
      <IosSegmented
        className="mx-4 mb-5"
        label={t("salaryType")}
        value={settings.salaryType}
        onChange={(salaryType) => update({ salaryType })}
        options={[
          { value: "monthly", label: t("monthly") },
          { value: "daily", label: t("daily") },
        ]}
      />

      <IosGroup note={t("salaryPrivacyNote")}>
        <NumberFieldRow
          label={t("amount")}
          value={settings.salaryAmount}
          placeholder="0"
          onChange={setAmount}
          separator
          emphasis
        />
        {settings.salaryType === "monthly" && (
          <NumberFieldRow
            label={t("monthlyWorkingDays")}
            value={settings.monthlyWorkingDays}
            placeholder="21.75"
            onChange={(monthlyWorkingDays) => update({ monthlyWorkingDays })}
            separator
          />
        )}
        <IosRow
          label={t("hideEarnings")}
          detail={
            <IosSwitch
              checked={settings.hideEarnings}
              onChange={(hideEarnings) => update({ hideEarnings })}
              label={t("hideEarnings")}
            />
          }
        />
      </IosGroup>

      {view.moneyEarned !== null && !settings.hideEarnings && (
        <div className="mx-4 mt-6 rounded-[22px] bg-[var(--ios-grouped)] p-4">
          <div className="text-[13px] text-[var(--ios-label-2)]">
            {t("moneyEarned")}
          </div>
          <div
            dir="ltr"
            className="mt-1.5 text-[32px] font-bold tabular-nums text-[var(--ios-title)]"
          >
            {formatMoney(lang, view.moneyEarned, true)}
          </div>
        </div>
      )}

      {dailySalary !== null && (
        <IosGroup title={t("derivedFromThis")} className="mt-5">
          <IosRow
            label={t("perWorkday")}
            value={formatMoney(lang, dailySalary, true)}
            numericValue
            separator
          />
          {hourlyRate !== null && (
            <IosRow
              label={t("perEffectiveHour")}
              value={formatMoney(lang, hourlyRate, true)}
              numericValue
            />
          )}
        </IosGroup>
      )}
    </IosSubpage>
  );
}

/**
 * A numeric row that keeps the raw string in state.
 *
 * Parsing on every keystroke would delete the intermediate states a person
 * types through — an empty field while retyping, or a bare decimal separator.
 * `lib/countdown.ts` rejects anything that is still not a number.
 */
function NumberFieldRow({
  label,
  value,
  placeholder,
  onChange,
  separator = false,
  emphasis = false,
}: {
  label: string;
  value: string;
  placeholder: string;
  onChange: (next: string) => void;
  separator?: boolean;
  emphasis?: boolean;
}) {
  return (
    <div
      className={`ios-row ios-row-flush min-h-[56px]${
        separator ? " ios-row-sep" : ""
      }`}
    >
      <label className="flex-1" htmlFor={`ios-field-${label}`}>
        {label}
      </label>
      <input
        id={`ios-field-${label}`}
        dir="ltr"
        type="text"
        inputMode="decimal"
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        className={`w-32 border-0 bg-transparent text-end tabular-nums outline-none placeholder:text-[var(--ios-label-3)] ${
          emphasis
            ? "text-[19px] font-semibold text-[var(--ios-label)]"
            : "text-[17px] text-[var(--ios-label-2)]"
        }`}
      />
    </div>
  );
}

/* ── Off-work notifications ────────────────────────────────────────────── */

function NotificationsSubpage({ lang, app, onBack, onOpen }: SubpageProps) {
  const { t } = useTranslation();
  const { settings, update } = app;
  // Only a real refusal earns the banner. The P1 bridge answers "unavailable",
  // which must stay silent — telling every user they had switched notifications
  // off would be reporting a platform gap as their own choice.
  const [denied, setDenied] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void getNotificationPermission().then((permission) => {
      if (!cancelled) setDenied(permission === "denied");
    });
    return () => {
      cancelled = true;
    };
  }, [settings.notificationMode]);

  const setMode = (notificationMode: NotificationMode) => {
    // Matches the macOS App Store feature model. P3 turns this into the native
    // absolute reminder projection and requests permission in context; until
    // then the choice is recorded and the denial banner only appears if the
    // platform actually reports a refusal.
    update({ notificationMode });
  };

  const modes: { value: NotificationMode; label: string }[] = [
    { value: "off", label: t("notificationModeOff") },
    { value: "simple", label: t("notificationModeSimple") },
    { value: "milestones", label: t("notificationModeMilestones") },
  ];

  return (
    <IosSubpage
      title={t("notificationMode")}
      backLabel={t("settings")}
      onBack={onBack}
    >
      {denied && (
        <div className="mx-4 mb-6 rounded-[22px] bg-[var(--ios-grouped)] p-4">
          <div className="flex items-start gap-3">
            <span className="inline-flex h-[38px] w-[38px] flex-none items-center justify-center rounded-xl bg-[var(--ios-accent-wash)] text-[var(--ios-accent-ink)]">
              <BellOff className="h-[19px] w-[19px]" />
            </span>
            <div>
              <div className="text-[17px] font-semibold tracking-[-0.43px] text-[var(--ios-label)]">
                {t("notificationDeniedTitle")}
              </div>
              <div className="mt-1 text-[15px] leading-snug text-[var(--ios-label-2)]">
                {t("notificationDeniedBody")}
              </div>
            </div>
          </div>
          <IosButton
            filled
            className="mt-3.5 h-11 w-full rounded-xl text-base"
            onClick={() => void openDesktopNotificationSettings()}
          >
            {t("notificationOpenSettings")}
          </IosButton>
        </div>
      )}

      <IosGroup>
        {modes.map((mode, index) => (
          <IosRow
            key={mode.value}
            label={mode.label}
            checked={settings.notificationMode === mode.value}
            separator={index < modes.length - 1}
            onClick={() => setMode(mode.value)}
          />
        ))}
      </IosGroup>

      <IosGroup
        title={t("liveActivity")}
        className="mt-4"
        note={t("liveActivityScheduleNote")}
      >
        <IosSwitchRow
          label={t("lockScreenLiveActivity")}
          checked={settings.liveActivityEnabled}
          onChange={(liveActivityEnabled) => update({ liveActivityEnabled })}
          separator
        />
        <IosRow
          label={t("lunchStartTime")}
          value={t("liveActivityLead", {
            count: settings.liveActivityLeadMinutes,
          })}
          chevron
          onClick={() => onOpen("liveActivityLead")}
        />
      </IosGroup>

      <IosGroup
        title={t("duringTheShift")}
        className="mt-4"
        note={t("notificationPrivacyNote")}
      >
        <IosSwitchRow
          label={t("lunchBreak")}
          checked={settings.lunchStartNotificationEnabled}
          onChange={(lunchStartNotificationEnabled) =>
            update({
              lunchStartNotificationEnabled,
              lunchEndNotificationEnabled: lunchStartNotificationEnabled
                ? settings.lunchEndNotificationEnabled
                : false,
            })
          }
          separator
        />
        <IosRow
          label={t("microBreakReminder")}
          value={
            settings.microBreakEnabled
              ? formatMinutes(lang, settings.microBreakIntervalMinutes)
              : t("disabledShort")
          }
          chevron
          onClick={() => onOpen("health")}
        />
      </IosGroup>
    </IosSubpage>
  );
}

/* ── Lunch break ───────────────────────────────────────────────────────── */

function LunchSubpage({ lang, app, onBack, onOpen }: SubpageProps) {
  const { t } = useTranslation();
  const { settings, update, plannedShift } = app;

  return (
    <IosSubpage title={t("lunchBreak")} backLabel={t("settings")} onBack={onBack}>
      <IosGroup
        note={
          settings.lunchEnabled && !plannedShift.lunchFitsInShift
            ? t("lunchOutsideShift")
            : t("lunchPauseNote")
        }
      >
        <IosSwitchRow
          label={t("lunchBreak")}
          checked={settings.lunchEnabled}
          onChange={(lunchEnabled) => update({ lunchEnabled })}
          separator={settings.lunchEnabled}
        />
        {settings.lunchEnabled && (
          <>
            <IosTimeField
              label={t("lunchStartTime")}
              value={settings.lunchStartTime}
              onChange={(lunchStartTime) => update({ lunchStartTime })}
              separator
            />
            <IosRow
              label={t("lunchDuration")}
              value={formatMinutes(lang, settings.lunchDurationMinutes)}
              chevron
              onClick={() => onOpen("lunchDuration")}
            />
          </>
        )}
      </IosGroup>

      {settings.lunchEnabled && (
        <IosGroup title={t("remindersSection")} className="mt-4">
          <IosSwitchRow
            label={t("lunchStartReminder")}
            checked={settings.lunchStartNotificationEnabled}
            onChange={(lunchStartNotificationEnabled) =>
              update({ lunchStartNotificationEnabled })
            }
            separator
          />
          <IosSwitchRow
            label={t("lunchEndReminder")}
            checked={settings.lunchEndNotificationEnabled}
            onChange={(lunchEndNotificationEnabled) =>
              update({ lunchEndNotificationEnabled })
            }
          />
        </IosGroup>
      )}
    </IosSubpage>
  );
}

/* ── Health reminder ───────────────────────────────────────────────────── */

function HealthSubpage({ lang, app, onBack, onOpen }: SubpageProps) {
  const { t } = useTranslation();
  const { settings, update } = app;

  return (
    <IosSubpage
      title={t("microBreakReminder")}
      backLabel={t("settings")}
      onBack={onBack}
    >
      <IosGroup note={t("microBreakEffectiveTimeNote")}>
        <IosSwitchRow
          label={t("microBreakReminder")}
          checked={settings.microBreakEnabled}
          onChange={(microBreakEnabled) => update({ microBreakEnabled })}
          separator={settings.microBreakEnabled}
        />
        {settings.microBreakEnabled && (
          <IosRow
            label={t("microBreakInterval")}
            value={formatMinutes(lang, settings.microBreakIntervalMinutes)}
            chevron
            onClick={() => onOpen("microBreakInterval")}
          />
        )}
      </IosGroup>
    </IosSubpage>
  );
}

/* ── Value pickers ─────────────────────────────────────────────────────── */

function LunchDurationSubpage({ lang, app, onBack }: SubpageProps) {
  const { t } = useTranslation();
  return (
    <IosChoiceSubpage
      title={t("lunchDuration")}
      backLabel={t("lunchBreak")}
      onBack={onBack}
      value={app.settings.lunchDurationMinutes}
      onSelect={(lunchDurationMinutes) => app.update({ lunchDurationMinutes })}
      options={LUNCH_DURATIONS.map((minutes) => ({
        value: minutes,
        label: approximateDuration(lang, minutes * MINUTE_MS),
      }))}
    />
  );
}

function MicroBreakIntervalSubpage({ lang, app, onBack }: SubpageProps) {
  const { t } = useTranslation();
  return (
    <IosChoiceSubpage
      title={t("microBreakInterval")}
      backLabel={t("microBreakReminder")}
      onBack={onBack}
      value={app.settings.microBreakIntervalMinutes}
      onSelect={(microBreakIntervalMinutes) =>
        app.update({ microBreakIntervalMinutes })
      }
      options={MICRO_BREAK_INTERVALS.map((minutes) => ({
        value: minutes,
        label: formatMinutes(lang, minutes),
      }))}
    />
  );
}

function LiveActivityLeadSubpage({ app, onBack }: SubpageProps) {
  const { t } = useTranslation();
  return (
    <IosChoiceSubpage
      title={t("liveActivity")}
      backLabel={t("notificationMode")}
      onBack={onBack}
      value={app.settings.liveActivityLeadMinutes}
      onSelect={(liveActivityLeadMinutes) =>
        app.update({ liveActivityLeadMinutes })
      }
      options={LIVE_ACTIVITY_LEAD_CHOICES.map((minutes) => ({
        value: minutes as number,
        label: t("liveActivityLead", { count: minutes }),
      }))}
    />
  );
}

/* ── Appearance ────────────────────────────────────────────────────────── */

function ThemeSubpage({ app, onBack }: SubpageProps) {
  const { t } = useTranslation();
  return (
    <IosChoiceSubpage
      title={t("theme")}
      backLabel={t("settings")}
      onBack={onBack}
      value={app.settings.theme}
      onSelect={(theme) => app.update({ theme: theme as Theme })}
      options={THEMES.map((theme) => ({ value: theme, label: t(theme) }))}
    />
  );
}

function LanguageSubpage({ lang, onBack }: SubpageProps) {
  const { t } = useTranslation();

  const choose = (next: string) => {
    if (next === lang) {
      onBack();
      return;
    }
    try {
      localStorage.setItem(desktopLanguageStorageKey, next);
      // Language lives inside Settings; keep the user on that tab across the
      // full-document locale navigation the static export requires.
      sessionStorage.setItem(mobileSelectedTabStorageKey, "settings");
    } catch {
      // Neither the route change nor the tab restore is essential to switching.
    }
    // Mobile exports locale pages as sibling files (en.html, zh-CN.html, …), so
    // there is no Web-style /<locale> route to push. A full navigation also
    // lets the new document set <html lang/dir> before first paint, which
    // matters when switching to or from Arabic.
    window.location.assign(new URL(`${next}.html`, window.location.href).href);
  };

  return (
    <IosChoiceSubpage
      title={t("chooselanguage")}
      backLabel={t("settings")}
      onBack={onBack}
      value={lang}
      onSelect={choose}
      options={locales.map((locale) => ({
        value: locale as string,
        label: languageNames[locale] ?? locale,
      }))}
    />
  );
}
