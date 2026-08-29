"use client";

import { useEffect, useState } from "react";
import { Download, Monitor, X } from "lucide-react";
import { AnimatePresence, motion } from "framer-motion";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import { officialPageUrl } from "@/lib/site-urls";
import { track } from "@/lib/track";

const DISMISS_KEY = "desktop-download-invite-v1-dismissed";

export function DesktopDownloadInvite() {
  const { t, i18n } = useTranslation();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (localStorage.getItem(DISMISS_KEY)) return;

    const userAgent = navigator.userAgent.toLowerCase();
    const isTouchMac = /macintosh/.test(userAgent) && navigator.maxTouchPoints > 1;
    const isSupportedDesktop = /windows nt|macintosh/.test(userAgent) && !isTouchMac;
    if (!isSupportedDesktop) return;

    const timer = window.setTimeout(() => {
      setVisible(true);
      track("desktop_invite_view");
    }, 3000);
    return () => window.clearTimeout(timer);
  }, []);

  const dismiss = () => {
    localStorage.setItem(DISMISS_KEY, "true");
    setVisible(false);
    track("desktop_invite_dismiss");
  };

  const openDownloads = () => {
    localStorage.setItem(DISMISS_KEY, "true");
    setVisible(false);
    track("desktop_invite_open");
  };

  const downloadHref = officialPageUrl(i18n.language, "download");

  return (
    <AnimatePresence>
      {visible && (
        <motion.aside
          role="dialog"
          aria-labelledby="desktop-download-invite-title"
          initial={{ y: 28, opacity: 0, scale: 0.98 }}
          animate={{ y: 0, opacity: 1, scale: 1 }}
          exit={{ y: 24, opacity: 0, scale: 0.98 }}
          transition={{ duration: 0.22, ease: "easeOut" }}
          className="fixed inset-x-3 bottom-3 z-50 sm:left-auto sm:right-5 sm:w-[410px]"
        >
          <div className="overflow-hidden rounded-2xl border border-gray-200/90 bg-white/95 p-4 shadow-2xl shadow-black/15 backdrop-blur-xl dark:border-gray-700 dark:bg-gray-900/95">
            <div className="flex items-start gap-3">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-gray-950 text-white dark:bg-white dark:text-gray-950">
                <Monitor className="h-5 w-5" aria-hidden="true" />
              </span>
              <div className="min-w-0 flex-1">
                <h2
                  id="desktop-download-invite-title"
                  className="font-semibold tracking-tight text-gray-950 dark:text-white"
                >
                  {t("desktopInviteTitle")}
                </h2>
                <p className="mt-1 text-sm leading-5 text-gray-600 dark:text-gray-300">
                  {t("desktopInviteDescription")}
                </p>
              </div>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                onClick={dismiss}
                className="-mr-2 -mt-2 h-8 w-8 shrink-0 rounded-lg text-gray-500"
              >
                <X className="h-4 w-4" aria-hidden="true" />
                <span className="sr-only">{t("notNow")}</span>
              </Button>
            </div>

            <Button asChild className="mt-4 w-full gap-2 rounded-xl">
              <a
                href={downloadHref}
                target="_blank"
                rel="noopener noreferrer"
                onClick={openDownloads}
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
