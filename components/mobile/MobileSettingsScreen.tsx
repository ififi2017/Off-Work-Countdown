"use client";

import { useTranslation } from "react-i18next";
import {
  BellRing,
  Code,
  Coffee,
  Coins,
  GlassWater,
  Globe,
  Info,
  Monitor,
  Moon,
  RectangleHorizontal,
  Sun,
  Sunset,
  Tag,
  Zap,
} from "lucide-react";
import { siteConfig } from "@/config/site";
import { officialHomeUrl, officialPageUrl } from "@/lib/site-urls";
import { formatMinutes } from "@/lib/mobile/format";
import type { IosAppState } from "@/lib/mobile/use-ios-app";
import { languageNames } from "@/i18n-config";
import { IosGroup, IosRow } from "./ios-kit";
import { openExternal } from "./open-external";
import type { SubpageId } from "./subpage-ids";

const THEME_ICONS = {
  light: Sun,
  dark: Moon,
  auto: Monitor,
  cyberpunk: Zap,
  sunset: Sunset,
} as const;

/**
 * Settings holds preferences only. The shift itself is set on the Timer tab, so
 * there is never a second place that edits the same hours.
 */
export function MobileSettingsScreen({
  lang,
  app,
  onOpen,
  header,
  columns = false,
}: {
  lang: string;
  app: IosAppState;
  onOpen: (page: SubpageId) => void;
  header: React.ReactNode;
  /** Landscape and iPad lay the same groups out in two columns. */
  columns?: boolean;
}) {
  const { t } = useTranslation();
  const { settings } = app;
  const ThemeIcon = THEME_ICONS[settings.theme];

  return (
    <>
      {header}
      <div className={`ios-scroll pb-4${columns ? " ios-settings-columns" : ""}`}>
        <IosGroup title={t("appearanceSection")}>
          <IosRow
            icon={ThemeIcon}
            label={t("theme")}
            value={t(settings.theme)}
            chevron
            separator
            onClick={() => onOpen("theme")}
          />
          <IosRow
            icon={Globe}
            label={t("chooselanguage")}
            value={languageNames[lang as keyof typeof languageNames] ?? lang}
            chevron
            onClick={() => onOpen("language")}
          />
        </IosGroup>

        <IosGroup title={t("shiftSection")}>
          <IosRow
            icon={Coffee}
            label={t("lunchBreak")}
            value={
              settings.lunchEnabled
                ? `${settings.lunchStartTime} · ${formatMinutes(
                    lang,
                    settings.lunchDurationMinutes
                  )}`
                : t("disabledShort")
            }
            numericValue={settings.lunchEnabled}
            chevron
            separator
            onClick={() => onOpen("lunch")}
          />
          <IosRow
            icon={GlassWater}
            label={t("microBreakReminder")}
            value={
              settings.microBreakEnabled
                ? formatMinutes(lang, settings.microBreakIntervalMinutes)
                : t("disabledShort")
            }
            chevron
            separator
            onClick={() => onOpen("health")}
          />
          <IosRow
            icon={Coins}
            label={t("salarySettings")}
            value={
              settings.showSalary
                ? t(settings.salaryType === "daily" ? "daily" : "monthly")
                : t("disabledShort")
            }
            chevron
            onClick={() => onOpen("salary")}
          />
        </IosGroup>

        <IosGroup title={t("remindersSection")}>
          <IosRow
            icon={BellRing}
            label={t("notificationMode")}
            value={t(
              settings.notificationMode === "off"
                ? "notificationModeOff"
                : settings.notificationMode === "simple"
                  ? "notificationModeSimple"
                  : "notificationModeMilestones"
            )}
            chevron
            separator
            onClick={() => onOpen("notifications")}
          />
          <IosRow
            icon={RectangleHorizontal}
            label={t("liveActivity")}
            value={
              settings.liveActivityEnabled
                ? t("liveActivityLead", {
                    count: settings.liveActivityLeadMinutes,
                  })
                : t("disabledShort")
            }
            chevron
            onClick={() => onOpen("notifications")}
          />
        </IosGroup>

        <IosGroup title={t("aboutSection")}>
          <IosRow
            icon={Info}
            label={t("aboutProject")}
            external
            separator
            onClick={() =>
              openExternal(officialPageUrl(lang, "about"))
            }
          />
          <IosRow
            icon={Monitor}
            label={t("downloadDesktopApp")}
            external
            separator
            onClick={() =>
              openExternal(officialPageUrl(lang, "download"))
            }
          />
          <IosRow
            icon={Globe}
            label={t("visitOfficialWebsite")}
            external
            separator
            onClick={() => openExternal(officialHomeUrl(lang))}
          />
          <IosRow
            icon={Code}
            label={t("githubRepository")}
            external
            separator
            onClick={() => openExternal(siteConfig.github)}
          />
          <IosRow
            icon={Tag}
            label={t("version")}
            value={process.env.NEXT_PUBLIC_APP_VERSION}
            numericValue
          />
        </IosGroup>
      </div>
    </>
  );
}
