"use client";

import { useEffect, useState } from "react";
import {
  Apple,
  ArrowUpRight,
  Download,
  Github,
  LoaderCircle,
  MonitorDown,
  Sparkles,
  Store,
} from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { MacAppStoreDialog } from "@/components/MacAppStoreDialog";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { DOWNLOAD_MIRROR_HOST, mirroredDownloadUrl } from "@/lib/download-mirror";
import { cn } from "@/lib/utils";
import type { LatestReleaseDownloads, DownloadAsset } from "@/lib/github-release";
import type { ContentBundle } from "@/lib/server/content";
import { track } from "@/lib/track";
import type { TrackedEvent } from "@/lib/analytics-events";

type Copy = ContentBundle["download"];

interface DesktopDownloadsProps {
  copy: Copy;
  releasesUrl: string;
  storeUrl: string;
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
  href,
  label,
  downloadLabel,
  comingSoonLabel,
  unavailableLabel,
  loading,
  loadingLabel,
  event,
  badgeLabel,
  placeholder = false,
  compactLabel = false,
  variant = "default",
  className,
}: {
  asset: DownloadAsset | null | undefined;
  href?: string;
  label: string;
  downloadLabel: string;
  comingSoonLabel: string;
  unavailableLabel: string;
  loading: boolean;
  loadingLabel: string;
  event: TrackedEvent;
  badgeLabel?: string;
  placeholder?: boolean;
  compactLabel?: boolean;
  variant?: "default" | "outline";
  className?: string;
}) {
  if (!asset) {
    return (
      <div
        aria-disabled="true"
        aria-label={`${label} — ${loading ? loadingLabel : placeholder ? comingSoonLabel : unavailableLabel}`}
        title={loading ? loadingLabel : placeholder ? comingSoonLabel : unavailableLabel}
        className={cn(
          buttonVariants({ variant: "outline" }),
          "h-auto min-h-12 w-full cursor-not-allowed justify-between gap-3 border-gray-200 bg-gray-50 px-4 py-3 text-gray-400 opacity-80 dark:border-gray-700 dark:bg-gray-900/60 dark:text-gray-500"
        )}
      >
        <span className="inline-flex items-center gap-2">
          {label}
          {badgeLabel && (
            <span className="rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-semibold leading-none text-blue-700 dark:bg-blue-950/70 dark:text-blue-300">
              {badgeLabel}
            </span>
          )}
        </span>
        {/* 加载时只留一个转圈：loadingLabel 是给顶部状态行写的整句话，塞进按钮
            会换行（x64／ARM64 并排之后只有半列宽），而且那句话顶上已经说过一遍，
            四个按钮再各说一遍纯属重复。完整文案仍在 title 和 aria-label 里。 */}
        <span className="shrink-0 text-xs font-normal">
          {loading ? (
            <LoaderCircle className="h-4 w-4 animate-spin" aria-hidden="true" />
          ) : placeholder ? comingSoonLabel : "—"}
        </span>
      </div>
    );
  }

  return (
    <a
      href={href ?? asset.url}
      aria-label={`${downloadLabel} ${label}`}
      onClick={() => track(event)}
      className={cn(
        buttonVariants({ variant }),
        "h-auto min-h-12 w-full justify-between gap-3 px-4 py-3",
        className
      )}
    >
      <span className="inline-flex min-w-0 items-center gap-2 whitespace-nowrap">
        <Download className="h-4 w-4 shrink-0" aria-hidden="true" />
        {compactLabel ? label : `${downloadLabel} ${label}`}
        {badgeLabel && (
          <span className="rounded-full bg-primary-foreground/15 px-2 py-0.5 text-[10px] font-semibold leading-none text-primary-foreground">
            {badgeLabel}
          </span>
        )}
      </span>
      <span className="shrink-0 whitespace-nowrap text-xs font-normal opacity-70">
        {formatFileSize(asset.size)}
      </span>
    </a>
  );
}

export function DesktopDownloads({
  copy,
  releasesUrl,
  storeUrl,
}: DesktopDownloadsProps) {
  // 商店入口先说明独有的小组件与系统要求，再把用户带到推荐渠道。
  const [macDialogOpen, setMacDialogOpen] = useState(false);
  const [state, setState] = useState<ReleaseState>({ status: "loading" });
  // 默认直连，和客户端更新器「直连优先、失败才回落镜像」的取向一致。
  // 浏览器这边探测不到「下载很慢」，所以由用户自己决定。
  const [useMirror, setUseMirror] = useState(false);

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
  const hrefFor = (asset: DownloadAsset | null | undefined) =>
    asset && useMirror ? mirroredDownloadUrl(asset.url) : undefined;
  const linuxDownloadsEnabled = false;
  // 商店渠道在构建期把镜像模块换成空实现，此时没有镜像可选。开关留着会变成一个
  // 点了没反应的按钮，说明文字里的主机名也会渲染成空白，所以整块不渲染。
  const mirrorAvailable = DOWNLOAD_MIRROR_HOST.length > 0;

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

      {/* 镜像开关。只改下载地址，不碰体积、埋点和禁用态。 */}
      {mirrorAvailable && (
        <div className="mb-5 rounded-2xl border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-800">
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <Label
                htmlFor="download-mirror"
                className="font-medium text-gray-950 dark:text-white"
              >
                {copy.mirrorLabel}
              </Label>
              <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {copy.mirrorHint}
              </p>
            </div>
            <Switch
              id="download-mirror"
              checked={useMirror}
              onCheckedChange={setUseMirror}
            />
          </div>
          {useMirror && (
            <p className="mt-3 border-t border-gray-100 pt-3 text-sm text-amber-700 dark:border-gray-700 dark:text-amber-400">
              {copy.mirrorNotice.replace("{host}", DOWNLOAD_MIRROR_HOST)}
            </p>
          )}
        </div>
      )}

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
            {/* 商店排在直链之上：三条 Windows 产线里只有它自动更新，装的时候
                也不会撞上 SmartScreen。放在 Windows 卡片内部而不是整页最前——
                它本来就是 Windows 的事，单独占一行会让 Mac 用户以为走错了页。 */}
            <a
              href={storeUrl}
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => track("desktop_download_msstore")}
              className={cn(
                buttonVariants(),
                "h-auto min-h-12 w-full justify-between gap-3 bg-blue-600 px-4 py-3 text-white hover:bg-blue-700"
              )}
            >
              <span className="inline-flex items-center gap-2">
                <Store className="h-4 w-4" aria-hidden="true" />
                {copy.storeCtaLabel}
              </span>
              <ArrowUpRight className="h-4 w-4 opacity-70" aria-hidden="true" />
            </a>
            {/* 两个直链并排，标签用短名（"x64"／"ARM64"）：半列宽度放不下
                「下载 Windows x64 推荐 5.0 MB」那一整串。 */}
            <div className="grid gap-2.5 sm:grid-cols-2">
              <DownloadButton
                asset={downloads?.windowsX64}
                href={hrefFor(downloads?.windowsX64)}
                label={copy.windowsX64ShortLabel}
                downloadLabel={copy.downloadLabel}
                comingSoonLabel={copy.comingSoonLabel}
                unavailableLabel={copy.unavailableLabel}
                loading={loading}
                loadingLabel={copy.loadingLabel}
                event="desktop_download_windows_intel"
                variant="outline"
                compactLabel
                // 两条直链里 x64 适用绝大多数机器。用一圈很淡的蓝色光晕带出这个
                // 优先级，而不是再挂一个「推荐」徽章——商店那条已经是卡片里唯一
                // 的实心按钮，再加一个文字标记会让三个元素互相争夺注意力。
                className="border-blue-300 shadow-[0_0_0_3px_rgba(37,99,235,0.09)] hover:border-blue-400 dark:border-blue-800 dark:shadow-[0_0_0_3px_rgba(96,165,250,0.14)] dark:hover:border-blue-700"
              />
              <DownloadButton
                asset={downloads?.windowsArm64}
                href={hrefFor(downloads?.windowsArm64)}
                label={copy.windowsArmShortLabel}
                downloadLabel={copy.downloadLabel}
                comingSoonLabel={copy.comingSoonLabel}
                unavailableLabel={copy.unavailableLabel}
                loading={loading}
                loadingLabel={copy.loadingLabel}
                event="desktop_download_windows_arm"
                variant="outline"
                compactLabel
              />
            </div>
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
            {/* 与 Windows 卡片同构：推荐的商店渠道在上、直链在下。先用浮窗
                说明商店版独有的小组件，以及旧系统应改用直装版。 */}
            <button
              type="button"
              onClick={() => {
                track("desktop_macappstore_dialog_open");
                setMacDialogOpen(true);
              }}
              className={cn(
                buttonVariants(),
                "h-auto min-h-12 w-full justify-between gap-3 bg-zinc-900 px-4 py-3 text-white hover:bg-zinc-800 dark:bg-white dark:text-zinc-900 dark:hover:bg-zinc-200"
              )}
            >
              <span className="inline-flex items-center gap-2">
                <Apple className="h-4 w-4" aria-hidden="true" />
                {copy.macAppStoreCtaLabel}
              </span>
              <Sparkles className="h-4 w-4 opacity-70" aria-hidden="true" />
            </button>
            <div className="grid gap-2.5 sm:grid-cols-2">
              <DownloadButton
                asset={downloads?.macosAppleSilicon}
                href={hrefFor(downloads?.macosAppleSilicon)}
                label={copy.appleSiliconLabel}
                downloadLabel={copy.downloadLabel}
                comingSoonLabel={copy.comingSoonLabel}
                unavailableLabel={copy.unavailableLabel}
                loading={loading}
                loadingLabel={copy.loadingLabel}
                event="desktop_download_macos_apple"
                variant="outline"
                compactLabel
              />
              <DownloadButton
                asset={downloads?.macosIntel}
                href={hrefFor(downloads?.macosIntel)}
                label={copy.intelLabel}
                downloadLabel={copy.downloadLabel}
                comingSoonLabel={copy.comingSoonLabel}
                unavailableLabel={copy.unavailableLabel}
                loading={loading}
                loadingLabel={copy.loadingLabel}
                event="desktop_download_macos_intel"
                variant="outline"
                compactLabel
              />
            </div>
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
              href={hrefFor(downloads?.linuxX64)}
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

      <MacAppStoreDialog
        copy={copy}
        open={macDialogOpen}
        onOpenChange={setMacDialogOpen}
      />
    </div>
  );
}
