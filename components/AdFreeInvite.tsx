"use client";

import { useEffect, useState } from "react";
import { Download, Sparkles, X } from "lucide-react";
import { AnimatePresence, motion } from "framer-motion";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import { desktopInviteWillShow } from "@/components/DesktopDownloadInvite";
import { AD_CLOSED_EVENT } from "@/lib/ads";
import { officialDownloadUrlFromWeb } from "@/lib/site-urls";
import { track } from "@/lib/track";

/**
 * After a visitor closes an ad, a small card offers the ad-free apps. Once per
 * page view, and not while the desktop download invite is still on screen
 * (it already points at the apps and sits in the same corner).
 */
export function AdFreeInvite() {
  const { t, i18n } = useTranslation();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const onClose = () => {
      if (desktopInviteWillShow()) return;
      setVisible(true);
      track("ad_free_invite_view");
    };
    window.addEventListener(AD_CLOSED_EVENT, onClose, { once: true });
    return () => window.removeEventListener(AD_CLOSED_EVENT, onClose);
  }, []);

  return (
    <AnimatePresence>
      {visible && (
        <motion.aside
          role="dialog"
          aria-labelledby="ad-free-invite-title"
          initial={{ y: 28, opacity: 0, scale: 0.98 }}
          animate={{ y: 0, opacity: 1, scale: 1 }}
          exit={{ y: 24, opacity: 0, scale: 0.98 }}
          transition={{ duration: 0.22, ease: "easeOut" }}
          className="fixed inset-x-3 bottom-[calc(0.75rem+var(--ad-anchor-h,0px))] z-50 sm:left-auto sm:right-5 sm:w-[380px]"
        >
          <div className="overflow-hidden rounded-2xl border border-gray-200/90 bg-white/95 p-4 shadow-2xl shadow-black/15 backdrop-blur-xl dark:border-gray-700 dark:bg-gray-900/95">
            <div className="flex items-start gap-3">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-gray-950 text-white dark:bg-white dark:text-gray-950">
                <Sparkles className="h-5 w-5" aria-hidden="true" />
              </span>
              <div className="min-w-0 flex-1">
                <h2
                  id="ad-free-invite-title"
                  className="font-semibold tracking-tight text-gray-950 dark:text-white"
                >
                  {t("adFreeInviteTitle")}
                </h2>
                <p className="mt-1 text-sm leading-5 text-gray-600 dark:text-gray-300">
                  {t("adFreeInviteDescription")}
                </p>
              </div>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                onClick={() => setVisible(false)}
                className="-mr-2 -mt-2 h-8 w-8 shrink-0 rounded-lg text-gray-500"
              >
                <X className="h-4 w-4" aria-hidden="true" />
                <span className="sr-only">{t("notNow")}</span>
              </Button>
            </div>

            <Button asChild className="mt-4 w-full gap-2 rounded-xl">
              <a
                href={officialDownloadUrlFromWeb(i18n.language)}
                target="_blank"
                rel="noopener noreferrer"
                onClick={() => {
                  setVisible(false);
                  track("ad_free_invite_open");
                }}
              >
                <Download className="h-4 w-4" aria-hidden="true" />
                {t("desktopInviteButton")}
              </a>
            </Button>
          </div>
        </motion.aside>
      )}
    </AnimatePresence>
  );
}
