"use client";

import { useState } from "react";
import { MacAppStoreDialog } from "@/components/MacAppStoreDialog";
import type { MacAppStoreDialogCopy } from "@/lib/server/content";
import { track } from "@/lib/track";
import { cn } from "@/lib/utils";
import { IS_WEB_BUILD } from "@/lib/build-target";

interface MacAppStoreBadgeProps {
  copy: MacAppStoreDialogCopy;
  directInstallersHref: string;
  className?: string;
}

export function MacAppStoreBadge({
  copy,
  directInstallersHref,
  className,
}: MacAppStoreBadgeProps) {
  const [dialogOpen, setDialogOpen] = useState(false);

  if (!IS_WEB_BUILD) return null;

  return (
    <>
      <div className={cn("flex min-h-11 items-center", className)}>
        <button
          type="button"
          aria-label={copy.macAppStoreCtaLabel}
          onClick={() => {
            track("desktop_macappstore_dialog_open");
            setDialogOpen(true);
          }}
          className="block rounded-[7px] focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
        >
          {/* Apple 要求直接使用原始徽标图稿，并保持至少 40px 高。明暗主题只在
              官方黑、白两套图稿之间切换，不改色、不裁切、不重绘。 */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/badges/download-on-the-mac-app-store-black.svg"
            alt="Download on the Mac App Store"
            width="156.10054"
            height="40"
            className="block h-10 w-auto dark:hidden"
          />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/badges/download-on-the-mac-app-store-white.svg"
            alt=""
            aria-hidden="true"
            width="156.10054"
            height="40"
            className="hidden h-10 w-auto dark:block"
          />
        </button>
      </div>

      <MacAppStoreDialog
        copy={copy}
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        directInstallersHref={directInstallersHref}
      />
    </>
  );
}
