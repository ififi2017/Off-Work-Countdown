"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import { Share2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import type { Shift } from "@/lib/share";
import { track } from "@/lib/track";

// Code-split the dialog (pulls in qrcode + canvas logic) so it only loads
// when the user actually opens the share sheet.
const ShareDialog = dynamic(
  () => import("./ShareDialog").then((m) => m.ShareDialog),
  { ssr: false }
);

interface ShareButtonProps {
  timeLeft: string;
  progress: number;
  isOff: boolean;
  /** 随分享链接一起带出的班次，接收者打开即可看到同一个倒计时。 */
  shift: Shift;
  desktop?: boolean;
}

export function ShareButton({
  timeLeft,
  progress,
  isOff,
  shift,
  desktop = false,
}: ShareButtonProps) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [mounted, setMounted] = useState(false);

  return (
    <>
      <Button
        variant={desktop ? "default" : "outline"}
        className={desktop ? "h-9 rounded-lg px-4 shadow-sm" : undefined}
        onClick={() => {
          track("share_open");
          setMounted(true);
          setOpen(true);
        }}
      >
        <Share2 className="me-2 h-4 w-4" /> {t("shareButton")}
      </Button>
      {mounted && (
        <ShareDialog
          open={open}
          onOpenChange={setOpen}
          timeLeft={timeLeft}
          progress={progress}
          isOff={isOff}
          shift={shift}
          desktop={desktop}
        />
      )}
    </>
  );
}
