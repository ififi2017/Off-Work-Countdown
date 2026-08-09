"use client";

import { useEffect, useState } from "react";
import {
  Apple,
  Download,
  Github,
  LoaderCircle,
  MonitorDown,
} from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { LatestReleaseDownloads, DownloadAsset } from "@/lib/github-release";
import type { ContentBundle } from "@/lib/server/content";
import { track } from "@/lib/track";
import type { TrackedEvent } from "@/lib/analytics-events";

type Copy = ContentBundle["download"];

interface DesktopDownloadsProps {
  copy: Copy;
  releasesUrl: string;
}

type ReleaseState =
  | { status: "loading" }
  | { status: "ready"; release: LatestReleaseDownloads }
  | { status: "error" };

function formatFileSize(bytes: number): string {
  if (!bytes) return "";
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function DownloadButton({
  asset,
  label,
  downloadLabel,
  comingSoonLabel,
  unavailableLabel,
  loading,
  loadingLabel,
  event,
  placeholder = false,
}: {
  asset: DownloadAsset | null | undefined;
  label: string;
  downloadLabel: string;
  comingSoonLabel: string;
  unavailableLabel: string;
  loading: boolean;
  loadingLabel: string;
  event: TrackedEvent;
  placeholder?: boolean;
}) {
  if (!asset) {
    return (
      <div
        aria-disabled="true"
        title={loading ? loadingLabel : placeholder ? comingSoonLabel : unavailableLabel}
        className={cn(
          buttonVariants({ variant: "outline" }),
          "h-auto min-h-12 w-full cursor-not-allowed justify-between gap-3 border-gray-200 bg-gray-50 px-4 py-3 text-gray-400 opacity-80 dark:border-gray-700 dark:bg-gray-900/60 dark:text-gray-500"
        )}
      >
        <span>{label}</span>
        <span className="text-xs font-normal">
          {loading ? (
            <span className="inline-flex items-center gap-1.5">
              <LoaderCircle className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />
              {loadingLabel}
            </span>
          ) : placeholder ? comingSoonLabel : "—"}
        </span>
      </div>
    );
  }

  return (
    <a
      href={asset.url}
      onClick={() => track(event)}
      className={cn(
        buttonVariants(),
        "h-auto min-h-12 w-full justify-between gap-3 px-4 py-3"
      )}
    >
      <span className="inline-flex items-center gap-2">
        <Download className="h-4 w-4" aria-hidden="true" />
        {downloadLabel} {label}
      </span>
      <span className="text-xs font-normal opacity-70">
        {formatFileSize(asset.size)}
      </span>
    </a>
  );
}

export function DesktopDownloads({ copy, releasesUrl }: DesktopDownloadsProps) {
  const [state, setState] = useState<ReleaseState>({ status: "loading" });

  useEffect(() => {
    const controller = new AbortController();

    fetch("/api/releases/latest", { signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error(`Release lookup failed: ${response.status}`);
        return (await response.json()) as LatestReleaseDownloads;
      })
      .then((release) => setState({ status: "ready", release }))
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setState({ status: "error" });
      });

    return () => controller.abort();
  }, []);

  const downloads = state.status === "ready" ? state.release.downloads : null;
  const loading = state.status === "loading";
  const linuxDownloadsEnabled = false;

  return (
    <div>
      <div className="mb-5 flex min-h-6 items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
        {state.status === "loading" && (
          <>
            <LoaderCircle className="h-4 w-4 animate-spin" aria-hidden="true" />
            {copy.loadingLabel}
          </>
        )}
        {state.status === "ready" && (
          <>
            <span className="h-2 w-2 rounded-full bg-emerald-500" aria-hidden="true" />
            {copy.latestVersionLabel} {state.release.version}
          </>
        )}
        {state.status === "error" && (
          <span className="text-amber-700 dark:text-amber-400">
            {copy.unavailableLabel}
          </span>
        )}
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div className="mb-5 flex items-center gap-3">
            <span className="grid h-11 w-11 place-items-center rounded-xl bg-blue-50 text-blue-700 dark:bg-blue-950/60 dark:text-blue-300">
              <MonitorDown className="h-5 w-5" aria-hidden="true" />
            </span>
            <div>
              <h3 className="font-semibold text-gray-950 dark:text-white">
                {copy.windowsTitle}
              </h3>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {copy.windowsDescription}
              </p>
            </div>
          </div>
          <div className="space-y-2.5">
            <DownloadButton
              asset={downloads?.windowsX64}
              label={copy.windowsX64Label}
              downloadLabel={copy.downloadLabel}
              comingSoonLabel={copy.comingSoonLabel}
              unavailableLabel={copy.unavailableLabel}
              loading={loading}
              loadingLabel={copy.loadingLabel}
              event="desktop_download_windows_intel"
            />
            <DownloadButton
              asset={downloads?.windowsArm64}
              label={copy.windowsArmLabel}
              downloadLabel={copy.downloadLabel}
              comingSoonLabel={copy.comingSoonLabel}
              unavailableLabel={copy.unavailableLabel}
              loading={loading}
              loadingLabel={copy.loadingLabel}
              event="desktop_download_windows_arm"
            />
          </div>
        </section>

        <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div className="mb-5 flex items-center gap-3">
            <span className="grid h-11 w-11 place-items-center rounded-xl bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-100">
              <Apple className="h-5 w-5" aria-hidden="true" />
            </span>
            <div>
              <h3 className="font-semibold text-gray-950 dark:text-white">
                {copy.macosTitle}
              </h3>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {copy.macosDescription}
              </p>
            </div>
          </div>
          <div className="space-y-2.5">
            <DownloadButton
              asset={downloads?.macosAppleSilicon}
              label={copy.appleSiliconLabel}
              downloadLabel={copy.downloadLabel}
              comingSoonLabel={copy.comingSoonLabel}
              unavailableLabel={copy.unavailableLabel}
              loading={loading}
              loadingLabel={copy.loadingLabel}
              event="desktop_download_macos_apple"
            />
            <DownloadButton
              asset={downloads?.macosIntel}
              label={copy.intelLabel}
              downloadLabel={copy.downloadLabel}
              comingSoonLabel={copy.comingSoonLabel}
              unavailableLabel={copy.unavailableLabel}
              loading={loading}
              loadingLabel={copy.loadingLabel}
              event="desktop_download_macos_intel"
            />
          </div>
        </section>

        {/* Linux 的解析和文案已保留；发布 Linux 安装包后只需打开此开关。 */}
        {linuxDownloadsEnabled && (
          <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-800">
            <h3 className="font-semibold text-gray-950 dark:text-white">
              {copy.linuxTitle}
            </h3>
            <p className="mb-5 text-sm text-gray-500 dark:text-gray-400">
              {copy.linuxDescription}
            </p>
            <DownloadButton
              asset={downloads?.linuxX64}
              label={copy.linuxX64Label}
              downloadLabel={copy.downloadLabel}
              comingSoonLabel={copy.comingSoonLabel}
              unavailableLabel={copy.unavailableLabel}
              loading={loading}
              loadingLabel={copy.loadingLabel}
              event="desktop_download_linux_intel"
            />
          </section>
        )}
      </div>

      <a
        href={releasesUrl}
        target="_blank"
        rel="noopener noreferrer"
        onClick={() => track("desktop_download_github")}
        className="mt-5 flex items-center gap-3 rounded-2xl border border-gray-200 bg-white p-5 text-gray-900 transition-colors hover:border-gray-300 hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-800 dark:text-white dark:hover:border-gray-600 dark:hover:bg-gray-800/70"
      >
        <Github className="h-5 w-5 shrink-0" aria-hidden="true" />
        <span className="min-w-0 flex-1">
          <span className="block font-medium">{copy.githubLabel}</span>
          <span className="mt-0.5 block text-sm font-normal text-gray-500 dark:text-gray-400">
            {copy.githubDescription}
          </span>
        </span>
      </a>
    </div>
  );
}
