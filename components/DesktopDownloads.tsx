"use client";

import { useEffect, useState } from "react";
import {
  Apple,
  ArrowUpRight,
  Check,
  Download,
  Github,
  LoaderCircle,
  MonitorDown,
  Sparkles,
  Store,
} from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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
  macAppStoreUrl: string;
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
      onClick={() => track(event)}
      className={cn(
        buttonVariants({ variant }),
        "h-auto min-h-12 w-full justify-between gap-3 px-4 py-3",
        className
      )}
    >
      <span className="inline-flex items-center gap-2">
        <Download className="h-4 w-4" aria-hidden="true" />
        {downloadLabel} {label}
        {badgeLabel && (
          <span className="rounded-full bg-primary-foreground/15 px-2 py-0.5 text-[10px] font-semibold leading-none text-primary-foreground">
            {badgeLabel}
          </span>
        )}
      </span>
      <span className="text-xs font-normal opacity-70">
        {formatFileSize(asset.size)}
      </span>
    </a>
  );
}

export function DesktopDownloads({
  copy,
  releasesUrl,
  storeUrl,
  macAppStoreUrl,
}: DesktopDownloadsProps) {
  // 商店入口先解释再跳转：付费差异（小组件）不说清楚，用户点过去看到价格
  // 只会直接退回来。
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
            {/* 与 Windows 卡片同构：商店在上、直链在下。区别是这里不直接跳转——
                macOS 商店版是付费的，且多一个桌面小组件，先用浮窗把差异讲清楚。
                刻意不在按钮上标价：价格脱离「多了什么」单独出现，只会劝退。 */}
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

      {/* 付费说明浮窗。三件事按重要性排：先给小组件一张图（这是唯一花钱才有的
          东西，讲一百字不如看一眼），再列便利性，最后才提钱——而且用「请我喝杯
          咖啡」的说法，并在同一屏里明确告诉用户免费版一直都在。 */}
      <Dialog open={macDialogOpen} onOpenChange={setMacDialogOpen}>
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
            {/* 连桌面和 Dock 一起截，是因为单独一块组件浮在卡片上看不出它是
                「桌面上的东西」——正是这一点在跟免费版做区分。所以图不抠底、
                贴边铺满，让外层的圆角去裁它。
                用 dark: 显隐而不是 <picture> + prefers-color-scheme：应用的深色
                模式是 html 上的 class，跟系统偏好不一定一致。 */}
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

          {/* 只有前两条是「多出来的东西」。系统版本要求是前提，挂上同样的绿勾会
              读成第三个卖点，所以降级成脚注。 */}
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

          <p className="mx-6 mt-5 rounded-xl bg-amber-50 px-4 py-3 text-sm leading-6 text-amber-900 dark:bg-amber-950/40 dark:text-amber-200">
            {copy.macAppStoreCoffeeNote}
          </p>

          <div className="flex flex-col-reverse gap-2.5 px-6 pb-6 pt-5 sm:flex-row sm:justify-end">
            <button
              type="button"
              onClick={() => setMacDialogOpen(false)}
              className={cn(buttonVariants({ variant: "outline" }), "min-h-11")}
            >
              {copy.macAppStoreDialogSecondary}
            </button>
            <a
              href={macAppStoreUrl}
              target="_blank"
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
    </div>
  );
}
