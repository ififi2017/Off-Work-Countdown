"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import { Share2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";

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
}

export function ShareButton({ timeLeft, progress, isOff }: ShareButtonProps) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [mounted, setMounted] = useState(false);

  return (
    <>
      <Button
        variant="outline"
        onClick={() => {
          setMounted(true);
          setOpen(true);
        }}
      >
        <Share2 className="mr-2 h-4 w-4" /> {t("shareButton")}
      </Button>
      {mounted && (
        <ShareDialog
          open={open}
          onOpenChange={setOpen}
          timeLeft={timeLeft}
          progress={progress}
          isOff={isOff}
        />
      )}
    </>
  );
}
