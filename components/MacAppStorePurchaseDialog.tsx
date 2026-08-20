"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Apple, Check, Sparkles } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { siteConfig } from "@/config/site";
import type { MacAppStoreDialogCopy } from "@/lib/server/content";
import { track } from "@/lib/track";
import { cn } from "@/lib/utils";

interface MacAppStorePurchaseDialogProps {
  copy: MacAppStoreDialogCopy;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  freeVersionHref?: string;
}

export function MacAppStorePurchaseDialog({
  copy,
  open,
  onOpenChange,
  freeVersionHref,
}: MacAppStorePurchaseDialogProps) {
  const router = useRouter();
  const [isMacOS, setIsMacOS] = useState(false);

  useEffect(() => {
    // iPadOS 可能把自己报告为 Macintosh；触屏 Mac 判据和页面上的桌面下载邀请
    // 保持一致，避免把 iPad 用户送进只属于 macOS 的 URL scheme。
    const isTouchMac =
      /macintosh/i.test(navigator.userAgent) && navigator.maxTouchPoints > 1;
    setIsMacOS(/macintosh/i.test(navigator.userAgent) && !isTouchMac);
  }, []);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] gap-0 overflow-y-auto p-0 sm:max-w-lg">
        <DialogHeader className="px-6 pb-4 pt-6 text-left">
          <DialogTitle className="text-xl">
            {copy.macAppStoreDialogTitle}
          </DialogTitle>
          <DialogDescription className="pt-1 text-left leading-6">
            {copy.macAppStoreDialogIntro}
          </DialogDescription>
        </DialogHeader>

        <div className="mx-6 overflow-hidden rounded-2xl border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-800/60">
          <div className="flex items-start gap-3 px-4 pb-3 pt-4">
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-gray-900 text-white dark:bg-white dark:text-gray-900">
              <Sparkles className="h-4 w-4" aria-hidden="true" />
            </span>
            <div className="min-w-0">
              <p className="font-semibold text-gray-950 dark:text-white">
                {copy.macAppStoreWidgetHeading}
              </p>
              <p className="mt-1 text-sm leading-6 text-gray-600 dark:text-gray-300">
                {copy.macAppStoreWidgetBody}
              </p>
            </div>
          </div>
          {/* 真机桌面截图必须原样铺满，才能看出它是桌面组件而不是应用内卡片。 */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={copy.macAppStoreWidgetImageLight}
            alt={copy.macAppStoreWidgetAlt}
            className="block w-full dark:hidden"
            loading="lazy"
          />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={copy.macAppStoreWidgetImageDark}
            alt=""
            aria-hidden="true"
            className="hidden w-full dark:block"
            loading="lazy"
          />
        </div>

        <ul className="mt-5 space-y-2.5 px-6 text-sm text-gray-600 dark:text-gray-300">
          {[copy.macAppStorePerk1, copy.macAppStorePerk2].map((perk) => (
            <li key={perk} className="flex items-start gap-2.5">
              <Check
                className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600 dark:text-emerald-400"
                aria-hidden="true"
              />
              <span className="leading-6">{perk}</span>
            </li>
          ))}
        </ul>

        <p className="mt-3 px-6 pl-[2.375rem] text-xs leading-5 text-gray-500 dark:text-gray-400">
          {copy.macAppStorePerk3}
        </p>

        <div className="mx-6 mt-5 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3.5 text-emerald-950 dark:border-emerald-900 dark:bg-emerald-950/40 dark:text-emerald-100">
          <p className="text-lg font-semibold tracking-tight">
            {copy.macAppStorePriceLabel}
          </p>
          <p className="mt-1 text-sm leading-6">
            {copy.macAppStoreSupportNote}
          </p>
        </div>

        <div className="flex flex-col-reverse gap-2.5 px-6 pb-6 pt-5 sm:flex-row sm:justify-end">
          {freeVersionHref ? (
            <button
              type="button"
              onClick={() => {
                onOpenChange(false);
                router.push(freeVersionHref);
              }}
              className={cn(buttonVariants({ variant: "outline" }), "min-h-11")}
            >
              {copy.macAppStoreDialogSecondary}
            </button>
          ) : (
            <button
              type="button"
              onClick={() => onOpenChange(false)}
              className={cn(buttonVariants({ variant: "outline" }), "min-h-11")}
            >
              {copy.macAppStoreDialogSecondary}
            </button>
          )}
          <a
            href={isMacOS ? siteConfig.macAppStoreApp : siteConfig.macAppStore}
            target={isMacOS ? undefined : "_blank"}
            rel="noopener noreferrer"
            onClick={() => track("desktop_download_macappstore")}
            className={cn(buttonVariants(), "min-h-11 gap-2")}
          >
            <Apple className="h-4 w-4" aria-hidden="true" />
            {copy.macAppStoreDialogPrimary}
          </a>
        </div>
      </DialogContent>
    </Dialog>
  );
}
