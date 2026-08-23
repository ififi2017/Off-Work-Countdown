export function openUrl(): never {
  throw new Error("Tauri opener is unavailable in the iOS build");
}

export function locale(): never {
  throw new Error("Tauri OS locale is unavailable in the iOS build");
}

export function getVersion(): never {
  throw new Error("Tauri app metadata is unavailable in the iOS build");
}
