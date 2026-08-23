"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";
import { BellRing, Clock, RectangleHorizontal, WifiOff } from "lucide-react";
import { siteConfig } from "@/config/site";
import { IosButton } from "./ios-kit";
import type { NotificationMode } from "@/lib/mobile/use-ios-app";

/**
 * First launch: what the app is, then one question, then straight into the
 * shift. Permission itself is never requested here — it is asked in context,
 * the first time a reminder is actually switched on.
 */
export function MobileOnboarding({
  onFinish,
}: {
  onFinish: (notificationMode: NotificationMode | null) => void;
}) {
  const { t } = useTranslation();
  const [step, setStep] = useState<"intro" | "reminders">("intro");

  if (step === "intro") {
    return (
      <div className="flex min-h-0 flex-1 flex-col bg-[var(--ios-grouped)] pt-[env(safe-area-inset-top)]">
        <div className="ios-scroll flex flex-col items-center justify-center px-8 text-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/icon-192x192.png"
            alt=""
            className="h-24 w-24 rounded-3xl shadow-lg"
          />
          <h1 className="mt-6 text-[34px] font-bold leading-tight tracking-[-0.03em] text-[var(--ios-title)]">
            {siteConfig.name}
          </h1>
          <p className="mt-3 text-[17px] leading-snug text-[var(--ios-label-2)]">
            {t("landingTagline")}
          </p>

          <div className="mt-8 flex w-full flex-col gap-4 text-start">
            <Feature
              icon={Clock}
              title={t("landingFeature1Title")}
              body={t("onboardingShiftBody")}
            />
            <Feature
              icon={WifiOff}
              title={t("onboardingOfflineTitle")}
              body={t("onboardingOfflineBody")}
            />
            <Feature
              icon={RectangleHorizontal}
              title={t("onboardingSystemTitle")}
              body={t("onboardingSystemBody")}
            />
          </div>
        </div>
        <div className="px-5 pb-[max(44px,env(safe-area-inset-bottom))]">
          <IosButton
            filled
            className="w-full"
            onClick={() => setStep("reminders")}
          >
            {t("onboardingSetShift")}
          </IosButton>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col bg-[var(--ios-grouped)] pt-[env(safe-area-inset-top)]">
      <div className="ios-scroll flex flex-col justify-center px-7">
        <span className="inline-flex h-[52px] w-[52px] items-center justify-center rounded-2xl bg-[var(--ios-accent-wash)] text-[var(--ios-accent-ink)]">
          <BellRing className="h-6 w-6" />
        </span>
        <h1 className="mt-5 text-[30px] font-bold leading-tight tracking-[-0.03em] text-[var(--ios-title)]">
          {t("enableNotificationsTitle")}
        </h1>
        <p className="mt-3 text-[17px] leading-relaxed text-[var(--ios-label-2)]">
          {t("mobileNotificationPrimerBody")}
        </p>
        <p className="mt-3.5 text-[17px] font-semibold leading-relaxed text-[var(--ios-title)]">
          {t("notificationPrivacyNote")}
        </p>

        <div className="mt-7 overflow-hidden rounded-[20px] bg-[var(--ios-bg)]">
          <div className="ios-row ios-row-flush ios-row-sep">
            <span className="flex-1">{t("notificationModeSimple")}</span>
          </div>
          <div className="ios-row ios-row-flush ios-row-sep">
            <span className="flex-1">
              {t("liveActivityLead", { count: 15 })}
            </span>
          </div>
          <div className="ios-row ios-row-flush">
            <span className="flex-1 text-[var(--ios-label-2)]">
              {t("notificationModeMilestones")}
            </span>
          </div>
        </div>
      </div>
      <div className="flex flex-col gap-2.5 px-5 pb-[max(44px,env(safe-area-inset-bottom))]">
        <IosButton filled className="w-full" onClick={() => onFinish("simple")}>
          {t("notificationContinue")}
        </IosButton>
        <IosButton
          className="w-full bg-transparent font-medium text-[var(--ios-label-2)]"
          onClick={() => onFinish(null)}
        >
          {t("notNow")}
        </IosButton>
      </div>
    </div>
  );
}

function Feature({
  icon: Icon,
  title,
  body,
}: {
  icon: typeof Clock;
  title: string;
  body: string;
}) {
  return (
    <div className="flex items-start gap-3">
      <Icon className="mt-0.5 h-5 w-5 flex-none text-[var(--ios-title)]" />
      <div>
        <div className="text-base font-semibold text-[var(--ios-title)]">
          {title}
        </div>
        <div className="text-[15px] leading-snug text-[var(--ios-label-2)]">
          {body}
        </div>
      </div>
    </div>
  );
}
