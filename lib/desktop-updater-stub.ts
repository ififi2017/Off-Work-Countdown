// 系统商店渠道会把整层桌面更新适配器替换为本文件。这样 updater/process
// 插件和下载安装实现都不会进入静态导出，而不只是运行时不调用。

const UNREACHABLE =
  "desktop updater is unavailable in store builds; updates are handled by the system Store";

export function checkForDesktopUpdate(): never {
  throw new Error(UNREACHABLE);
}

export function relaunchAfterDesktopUpdate(): never {
  throw new Error(UNREACHABLE);
}
