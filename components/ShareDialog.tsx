"use client";

import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import { useTranslation } from "react-i18next";
import { track } from "@vercel/analytics";
import {
  SiX,
  SiFacebook,
  SiWhatsapp,
  SiTelegram,
  SiLine,
  SiReddit,
  SiSinaweibo,
} from "@icons-pack/react-simple-icons";
import { Download, Share2, Copy, Check, Image as ImageIcon, Type, Loader2 } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { moods, getMood } from "@/lib/moods";
import {
  buildShareUrl,
  buildShareText,
  platformShareUrl,
  canNativeShare,
  canNativeShareFiles,
  type SharePlatform,
} from "@/lib/share";
import { generateShareImage, type ShareFormat } from "@/lib/shareImage";
import { siteConfig } from "@/config/site";

interface ShareDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  timeLeft: string;
  progress: number;
  isOff: boolean;
}

const MOOD_STORAGE_KEY = "shareMood";
const IMAGE_FILENAME = "off-work-countdown.png";

type ImageState = {
  loading: boolean;
  url: string | null;
  blob: Blob | null;
  error: boolean;
};

const PLATFORMS: { id: SharePlatform; Icon: typeof SiX; label: string }[] = [
  { id: "x", Icon: SiX, label: "X" },
  { id: "facebook", Icon: SiFacebook, label: "Facebook" },
  { id: "whatsapp", Icon: SiWhatsapp, label: "WhatsApp" },
  { id: "telegram", Icon: SiTelegram, label: "Telegram" },
  { id: "line", Icon: SiLine, label: "LINE" },
  { id: "reddit", Icon: SiReddit, label: "Reddit" },
  { id: "weibo", Icon: SiSinaweibo, label: "Weibo" },
];

export function ShareDialog({
  open,
  onOpenChange,
  timeLeft,
  progress,
  isOff,
}: ShareDialogProps) {
  const { t } = useTranslation();
  const [tab, setTab] = useState<"image" | "text">("image");
  const [moodId, setMoodId] = useState(moods[0].id);
  const [format, setFormat] = useState<ShareFormat>("square");
  const [img, setImg] = useState<ImageState>({
    loading: true,
    url: null,
    blob: null,
    error: false,
  });
  const [copied, setCopied] = useState<"image" | "text" | null>(null);
  const urlRef = useRef<string | null>(null);

  const mood = getMood(moodId);
  const siteName = t("seo:siteName") || siteConfig.name;

  // The countdown ticks every second, but the share image is a snapshot — keep
  // the latest values in refs so ticking doesn't re-trigger image generation.
  const timeLeftRef = useRef(timeLeft);
  timeLeftRef.current = timeLeft;
  const progressRef = useRef(progress);
  progressRef.current = progress;

  // Restore last-used mood.
  useEffect(() => {
    try {
      const saved = localStorage.getItem(MOOD_STORAGE_KEY);
      if (saved) setMoodId(getMood(saved).id);
    } catch {
      // ignore
    }
  }, []);

  // Share text (with URL) for copy / native share, and the message-only variant
  // (emoji + line, no URL) for platform intent builders that append the URL.
  const shareUrl = useMemo(() => buildShareUrl("text"), []);
  const message = isOff
    ? t("shareOffWorkText")
    : t("shareText", { time: timeLeft });
  const textWithEmoji = `${mood.emoji} ${message}`;
  const fullText = buildShareText({ emoji: mood.emoji, message, url: shareUrl });

  // Regenerate the image whenever inputs change (image tab only).
  useEffect(() => {
    if (!open || tab !== "image") return;
    let cancelled = false;
    // Keep the previous image visible while regenerating so the preview box
    // doesn't flash empty or change height when switching mood/format.
    setImg((prev) => ({ ...prev, loading: true, error: false }));

    generateShareImage({
      timeLeft: isOff ? t("offWorkTime") : timeLeftRef.current,
      headline: isOff ? "" : t("shareImageHeadline"),
      siteName,
      url: buildShareUrl("image"),
      mood,
      format,
      progress: progressRef.current,
    })
      .then((res) => {
        if (cancelled) {
          URL.revokeObjectURL(res.objectUrl);
          return;
        }
        if (urlRef.current) URL.revokeObjectURL(urlRef.current);
        urlRef.current = res.objectUrl;
        setImg({ loading: false, url: res.objectUrl, blob: res.blob, error: false });
      })
      .catch(() => {
        if (!cancelled) setImg({ loading: false, url: null, blob: null, error: true });
      });

    return () => {
      cancelled = true;
    };
    // Intentionally excludes timeLeft/progress (read via refs) so the per-second
    // countdown tick does not regenerate the image.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, tab, moodId, format, isOff]);

  // Revoke the object URL on unmount.
  useEffect(() => () => {
    if (urlRef.current) URL.revokeObjectURL(urlRef.current);
  }, []);

  const flash = useCallback((which: "image" | "text") => {
    setCopied(which);
    setTimeout(() => setCopied(null), 1600);
  }, []);

  const chooseMood = (id: string) => {
    setMoodId(id);
    try {
      localStorage.setItem(MOOD_STORAGE_KEY, id);
    } catch {
      // ignore
    }
  };

  const handleDownload = () => {
    if (!img.url) return;
    const a = document.createElement("a");
    a.href = img.url;
    a.download = IMAGE_FILENAME;
    document.body.appendChild(a);
    a.click();
    a.remove();
    track("share", { platform: "download", mood: moodId, type: "image" });
  };

  const handleNativeShareImage = async () => {
    if (!img.blob) return;
    const file = new File([img.blob], IMAGE_FILENAME, { type: "image/png" });
    if (canNativeShareFiles([file])) {
      try {
        await navigator.share({ files: [file], text: fullText, title: siteName });
        track("share", { platform: "native", mood: moodId, type: "image" });
      } catch {
        // user cancelled — no-op
      }
    } else {
      handleDownload();
    }
  };

  const canCopyImage =
    typeof window !== "undefined" &&
    typeof ClipboardItem !== "undefined" &&
    !!navigator.clipboard?.write;

  const handleCopyImage = async () => {
    if (!img.blob || !canCopyImage) return;
    try {
      await navigator.clipboard.write([
        new ClipboardItem({ [img.blob.type]: img.blob }),
      ]);
      flash("image");
      track("share", { platform: "copy-image", mood: moodId, type: "image" });
    } catch {
      // ignore
    }
  };

  const handleCopyText = async () => {
    try {
      await navigator.clipboard.writeText(fullText);
      flash("text");
      track("share", { platform: "copy-text", mood: moodId, type: "text" });
    } catch {
      // ignore
    }
  };

  const handleNativeShareText = async () => {
    if (!canNativeShare()) return;
    try {
      await navigator.share({ text: fullText, title: siteName });
      track("share", { platform: "native", mood: moodId, type: "text" });
    } catch {
      // cancelled
    }
  };

  const handlePlatform = (id: SharePlatform) => {
    window.open(
      platformShareUrl[id](textWithEmoji, shareUrl),
      "_blank",
      "noopener,noreferrer"
    );
    track("share", { platform: id, mood: moodId, type: tab });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{t("shareTitle")}</DialogTitle>
          <DialogDescription className="sr-only">
            {t("shareTitle")}
          </DialogDescription>
        </DialogHeader>

        {/* Tabs: image / text */}
        <div className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1">
          <button
            type="button"
            onClick={() => setTab("image")}
            className={`flex items-center justify-center gap-2 rounded-md py-1.5 text-sm font-medium transition-colors ${
              tab === "image"
                ? "bg-background shadow-sm"
                : "text-muted-foreground hover:text-foreground"
            }`}
          >
            <ImageIcon className="h-4 w-4" /> {t("shareTabImage")}
          </button>
          <button
            type="button"
            onClick={() => setTab("text")}
            className={`flex items-center justify-center gap-2 rounded-md py-1.5 text-sm font-medium transition-colors ${
              tab === "text"
                ? "bg-background shadow-sm"
                : "text-muted-foreground hover:text-foreground"
            }`}
          >
            <Type className="h-4 w-4" /> {t("shareTabText")}
          </button>
        </div>

        {/* Mood picker */}
        <div>
          <p className="mb-2 text-xs font-medium text-muted-foreground">
            {t("shareMoodLabel")}
          </p>
          <div className="flex flex-wrap justify-center gap-2">
            {moods.map((m) => (
              <button
                key={m.id}
                type="button"
                onClick={() => chooseMood(m.id)}
                title={t(m.labelKey)}
                aria-label={t(m.labelKey)}
                aria-pressed={m.id === moodId}
                className={`flex h-10 w-10 items-center justify-center rounded-lg text-2xl transition-transform hover:scale-110 ${
                  m.id === moodId
                    ? "ring-2 ring-primary ring-offset-2 ring-offset-background"
                    : "bg-muted"
                }`}
              >
                {m.emoji}
              </button>
            ))}
          </div>
        </div>

        {tab === "image" ? (
          <div className="space-y-3">
            {/* Format toggle */}
            <div className="flex gap-2">
              {(["square", "story"] as ShareFormat[]).map((f) => (
                <button
                  key={f}
                  type="button"
                  onClick={() => setFormat(f)}
                  className={`flex-1 rounded-md border py-1.5 text-sm transition-colors ${
                    format === f
                      ? "border-primary bg-primary/10 text-foreground"
                      : "border-input text-muted-foreground hover:text-foreground"
                  }`}
                >
                  {f === "square" ? t("shareFormatSquare") : t("shareFormatStory")}
                </button>
              ))}
            </div>

            {/* Preview — fixed height so switching mood/format never shifts layout */}
            <div className="relative flex h-[320px] items-center justify-center overflow-hidden rounded-lg bg-muted/40 p-2">
              {img.url && (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={img.url}
                  alt={t("shareTitle")}
                  className="max-h-full w-auto rounded-lg shadow-md"
                />
              )}
              {img.loading && (
                <div className="absolute inset-0 flex items-center justify-center bg-background/40">
                  <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
                </div>
              )}
              {!img.url && !img.loading && (
                <span className="text-sm text-muted-foreground">—</span>
              )}
            </div>

            {/* Image actions */}
            <div className="flex flex-wrap gap-2">
              <Button onClick={handleNativeShareImage} className="flex-1 gap-2" disabled={!img.blob}>
                <Share2 className="h-4 w-4" />
                {canNativeShare() ? t("shareNative") : t("shareDownload")}
              </Button>
              <Button variant="outline" size="icon" onClick={handleDownload} disabled={!img.url} title={t("shareDownload")} aria-label={t("shareDownload")}>
                <Download className="h-4 w-4" />
              </Button>
              {canCopyImage && (
                <Button variant="outline" size="icon" onClick={handleCopyImage} disabled={!img.blob} title={t("shareCopyImage")} aria-label={t("shareCopyImage")}>
                  {copied === "image" ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </Button>
              )}
            </div>
          </div>
        ) : (
          <div className="space-y-3">
            <textarea
              readOnly
              value={fullText}
              rows={4}
              className="w-full resize-none rounded-md border bg-background p-3 text-sm dark:border-gray-700"
            />
            <div className="flex gap-2">
              {canNativeShare() && (
                <Button onClick={handleNativeShareText} className="flex-1 gap-2">
                  <Share2 className="h-4 w-4" /> {t("shareNative")}
                </Button>
              )}
              <Button
                variant={canNativeShare() ? "outline" : "default"}
                onClick={handleCopyText}
                className="flex-1 gap-2"
              >
                {copied === "text" ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                {copied === "text" ? t("shareCopied") : t("shareCopyText")}
              </Button>
            </div>
          </div>
        )}

        {/* Platform buttons */}
        <div className="flex flex-wrap justify-center gap-2 border-t pt-4">
          {PLATFORMS.map(({ id, Icon, label }) => (
            <button
              key={id}
              type="button"
              onClick={() => handlePlatform(id)}
              title={label}
              aria-label={label}
              className="flex h-11 w-11 items-center justify-center rounded-full bg-muted text-foreground transition-colors hover:bg-accent"
            >
              <Icon className="h-5 w-5" />
            </button>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
