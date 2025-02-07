"use client";

import { useTranslation } from "react-i18next";
import { I18nProvider } from "@/components/I18nProvider";
import { usePathname } from "next/navigation";
import { motion } from "framer-motion";
import { WifiOff } from "lucide-react";

export default function Offline() {
  const pathname = usePathname();
  const lang = pathname?.split("/")[1] || "en";

  return (
    <I18nProvider lang={lang}>
      <OfflineContent />
    </I18nProvider>
  );
}

function OfflineContent() {
  const { t } = useTranslation();

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
      <motion.div
        initial={{ scale: 0.5, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.5 }}
        className="text-center p-8 rounded-2xl bg-white/80 dark:bg-gray-800/80 backdrop-blur-lg shadow-xl"
      >
        <motion.div
          initial={{ scale: 0.8 }}
          animate={{ scale: 1 }}
          transition={{
            repeat: Infinity,
            repeatType: "reverse",
            duration: 2,
          }}
          className="mb-6"
        >
          <WifiOff className="w-16 h-16 mx-auto text-gray-400 dark:text-gray-500" />
        </motion.div>
        <h1 className="text-2xl font-bold text-gray-800 dark:text-gray-200 mb-4">
          {t("offlineStatus")}
        </h1>
        <p className="text-gray-600 dark:text-gray-400">{t("return")}</p>
      </motion.div>
    </div>
  );
}
