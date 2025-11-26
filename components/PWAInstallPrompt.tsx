"use client";

import { useState, useEffect } from "react";
import { X, Share, Download } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { Button } from "@/components/ui/button";
import { useTranslation } from "react-i18next";

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

export function PWAInstallPrompt() {
  const { t } = useTranslation();
  const [showPrompt, setShowPrompt] = useState(false);
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [platform, setPlatform] = useState<"ios" | "mac" | "other">("other");

  useEffect(() => {
    // Check if user has already dismissed the prompt
    const isDismissed = localStorage.getItem("pwa-prompt-dismissed");
    if (isDismissed) return;

    // Check if already installed
    const isStandalone = window.matchMedia("(display-mode: standalone)").matches;
    const isIOSStandalone = (window.navigator as Navigator & { standalone?: boolean }).standalone;
    if (isStandalone || isIOSStandalone) return;

    // Detect iOS
    const userAgent = window.navigator.userAgent.toLowerCase();
    const isIosDevice = /iphone|ipad|ipod/.test(userAgent);
    // Detect MacOS Safari
    const isMacSafari = /macintosh/.test(userAgent) && /safari/.test(userAgent) && !/chrome|chromium|edg/.test(userAgent);
    
    if (isIosDevice) setPlatform("ios");
    else if (isMacSafari) setPlatform("mac");

    // Handle Chrome/Edge install prompt
    const handleBeforeInstallPrompt = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
      setShowPrompt(true);
    };

    window.addEventListener("beforeinstallprompt", handleBeforeInstallPrompt);

    // For iOS/Mac Safari, show prompt after a small delay if not installed
    if (isIosDevice || isMacSafari) {
      setTimeout(() => {
        setShowPrompt(true);
      }, 3000);
    }

    return () => {
      window.removeEventListener("beforeinstallprompt", handleBeforeInstallPrompt);
    };
  }, []);

  const handleInstallClick = async () => {
    if (!deferredPrompt) return;

    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    
    if (outcome === "accepted") {
      setShowPrompt(false);
    }
    setDeferredPrompt(null);
  };

  const handleDismiss = () => {
    setShowPrompt(false);
    localStorage.setItem("pwa-prompt-dismissed", "true");
  };

  return (
    <AnimatePresence>
      {showPrompt && (
        <motion.div
          initial={{ y: 100, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          exit={{ y: 100, opacity: 0 }}
          className="fixed bottom-4 left-4 right-4 z-50 md:left-auto md:right-4 md:w-96"
        >
          <div className="bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60 border rounded-lg shadow-lg p-4">
            <div className="flex items-start justify-between gap-4">
              <div className="flex-1">
                <h3 className="font-semibold text-lg mb-1 dark:text-white">{t("installPWA")}</h3>
                <p className="text-sm text-muted-foreground mb-3">
                  {t("installDescription")}
                </p>
                
                {platform === "ios" || platform === "mac" ? (
                  <div className="text-sm bg-muted/50 p-3 rounded-md space-y-2">
                    <p className="flex items-center gap-2">
                      1. {t("safariInstructions1")} <Share className="h-4 w-4" />
                    </p>
                    <p className="flex items-center gap-2">
                      2. {platform === "mac" ? t("safariInstructions2Mac") : t("safariInstructions2")}
                    </p>
                  </div>
                ) : (
                  <Button onClick={handleInstallClick} className="w-full sm:w-auto gap-2">
                    <Download className="h-4 w-4" />
                    {t("installButton")}
                  </Button>
                )}
              </div>
              <Button
                variant="ghost"
                size="icon"
                className="h-6 w-6 -mr-2 -mt-2"
                onClick={handleDismiss}
              >
                <X className="h-4 w-4" />
                <span className="sr-only">{t("notNow")}</span>
              </Button>
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
