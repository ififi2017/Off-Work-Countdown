export interface DesktopUpdateCandidate {
  version: string;
  currentVersion: string;
  download: () => Promise<void>;
  install: () => Promise<void>;
  apply: () => Promise<void>;
}

/** GitHub 渠道的更新适配器；系统商店构建会在模块解析层替换整个文件。 */
export async function checkForDesktopUpdate(
  timeoutMs: number
): Promise<DesktopUpdateCandidate | null> {
  const { check } = await import("@tauri-apps/plugin-updater");
  const update = await check({ timeout: timeoutMs });
  if (!update) return null;

  return {
    version: update.version,
    currentVersion: update.currentVersion,
    download: () => update.download(),
    install: () => update.install(),
    apply: () => update.downloadAndInstall(),
  };
}

export async function relaunchAfterDesktopUpdate(): Promise<void> {
  const { relaunch } = await import("@tauri-apps/plugin-process");
  await relaunch();
}
