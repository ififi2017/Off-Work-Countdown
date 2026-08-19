// Store bundles do not offer GitHub download mirroring. The download page is
// still part of Next's static export, so replace the helper at build time to
// keep the third-party endpoint out of the packaged resources as well.
export const DOWNLOAD_MIRROR_HOST = "";

export function mirroredDownloadUrl(url: string): string {
  return url;
}
