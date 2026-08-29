"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Loader2, Share2, X } from "lucide-react";
import { getMood, moods } from "@/lib/moods";
import {
  buildShareText,
  buildShareUrl,
  canNativeShareFiles,
  SHARE_IMAGE_FILENAME,
} from "@/lib/share";
import { generateShareImage } from "@/lib/shareImage";
import { siteConfig } from "@/config/site";
import { IosButton, IosSheet } from "./ios-kit";

const MOOD_STORAGE_KEY = "shareMood";
const IMAGE_FILENAME = SHARE_IMAGE_FILENAME;

/**
 * Share, handed to iOS.
 *
 * The app picks a mood and renders the image; `UIActivityViewController` — the
 * system share sheet the Web Share API opens inside Capacitor — takes it from
 * there. That is why there are no per-platform buttons here the way the Web
 * dialog has: every destination the phone knows about is already in the system
 * sheet, and none of them would have to be maintained here.
 */
export function MobileShareSheet({
  lang,
  onClose,
  timeLeft,
  progress,
  isOff,
  shift,
}: {
  lang: string;
  onClose: () => void;
  timeLeft: string;
  progress: number;
  isOff: boolean;
  shift: { start: string; end: string };
}) {
  const { t } = useTranslation();
  const [moodId, setMoodId] = useState(moods[0].id);
  const [image, setImage] = useState<{ url: string; blob: Blob } | null>(null);
  const [pending, setPending] = useState(true);
  const objectUrlRef = useRef<string | null>(null);

  useEffect(() => {
    try {
      const stored = localStorage.getItem(MOOD_STORAGE_KEY);
      if (stored) setMoodId(getMood(stored).id);
    } catch {
      // The default mood is a fine starting point.
    }
  }, []);

  const message = isOff
    ? t("shareOffWorkText")
    : t("shareText", { time: timeLeft });
  const url = buildShareUrl("image", shift);

  useEffect(() => {
    let cancelled = false;
    setPending(true);
    void generateShareImage({
      timeLeft: isOff ? t("offWorkTime") : timeLeft,
      headline: t("shareImageHeadline"),
      siteName: siteConfig.brandName,
      url,
      mood: getMood(moodId),
      format: "story",
      progress,
      logoSrc: "/icon-512x512.png",
    })
      .then((result) => {
        if (cancelled) {
          URL.revokeObjectURL(result.objectUrl);
          return;
        }
        if (objectUrlRef.current) URL.revokeObjectURL(objectUrlRef.current);
        objectUrlRef.current = result.objectUrl;
        setImage({ url: result.objectUrl, blob: result.blob });
      })
      .catch(() => {
        if (!cancelled) setImage(null);
      })
      .finally(() => {
        if (!cancelled) setPending(false);
      });

    return () => {
      cancelled = true;
    };
    // `progress` ticks every second; the image is deliberately not regenerated
    // for it — only a mood or shift change is worth redrawing for.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [moodId, timeLeft, isOff, url, t]);

  useEffect(
    () => () => {
      if (objectUrlRef.current) URL.revokeObjectURL(objectUrlRef.current);
    },
    []
  );

  const chooseMood = useCallback((id: string) => {
    setMoodId(id);
    try {
      localStorage.setItem(MOOD_STORAGE_KEY, id);
    } catch {
      // Remembering the mood is a convenience, not a requirement.
    }
  }, []);

  const share = useCallback(async () => {
    const text = buildShareText({ emoji: getMood(moodId).emoji, message, url });
    const file = image
      ? new File([image.blob], IMAGE_FILENAME, { type: "image/png" })
      : null;

    try {
      if (file && canNativeShareFiles([file])) {
        await navigator.share({ files: [file], text, title: siteConfig.name });
      } else {
        await navigator.share({ text, url, title: siteConfig.name });
      }
      onClose();
    } catch {
      // Dismissing the system sheet rejects the promise; that is not an error.
    }
  }, [image, message, moodId, onClose, url]);

  return (
    <IosSheet onClose={onClose} label={t("shareTitle")}>
      <div className="flex items-center justify-between px-5">
        <span className="text-[20px] font-bold tracking-[-0.02em] text-[var(--ios-title)]">
          {t("shareButton")}
        </span>
        <button
          type="button"
          onClick={onClose}
          aria-label={t("notNow")}
          className="inline-flex h-[30px] w-[30px] items-center justify-center rounded-full bg-[var(--ios-fill)] text-[var(--ios-label-2)]"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      <div
        role="radiogroup"
        aria-label={t("shareMoodLabel")}
        className="flex gap-2.5 overflow-x-auto px-4 pt-4"
      >
        {moods.map((mood) => (
          <button
            key={mood.id}
            type="button"
            role="radio"
            aria-checked={mood.id === moodId}
            aria-label={t(mood.labelKey)}
            onClick={() => chooseMood(mood.id)}
            className="flex-none rounded-full p-[3px] transition-opacity"
            style={
              mood.id === moodId
                ? {
                    background: "var(--ios-grouped)",
                    boxShadow: "0 0 0 2px var(--ios-title)",
                  }
                : { opacity: 0.75 }
            }
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={`/emoji/${mood.code}.png`}
              alt=""
              className="h-[38px] w-[38px]"
            />
          </button>
        ))}
      </div>

      <div className="flex justify-center px-4 pt-4">
        <div className="flex h-[310px] w-[248px] items-center justify-center overflow-hidden rounded-[20px] bg-[var(--ios-fill)]">
          {pending || !image ? (
            <Loader2 className="h-6 w-6 animate-spin text-[var(--ios-label-3)]" />
          ) : (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={image.url}
              alt=""
              className="h-full w-full object-cover"
            />
          )}
        </div>
      </div>

      <div className="px-4 pt-4">
        <IosButton
          filled
          icon={Share2}
          className="w-full"
          disabled={pending}
          onClick={() => void share()}
        >
          {t("shareNative")}
        </IosButton>
      </div>
      <p className="mx-5 mt-2.5 text-[13px] leading-snug text-[var(--ios-label-2)]">
        {t("sharePrivacyNote")}
      </p>
    </IosSheet>
  );
}
