import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const hooks = readFileSync(
  new URL("./installer-hooks.nsh", import.meta.url),
  "utf8"
);

const tauriConfig = JSON.parse(
  readFileSync(new URL("../tauri.conf.json", import.meta.url), "utf8")
) as {
  productName: string;
  identifier: string;
  mainBinaryName: string;
  bundle: { windows: { nsis: { installerHooks?: string } } };
};

describe("NSIS legacy productName reclaim", () => {
  it("keeps the new display name and the old Windows identities apart", () => {
    expect(tauriConfig.productName).toBe("DoneAt");
    expect(tauriConfig.mainBinaryName).toBe("Off Work Countdown");
    expect(tauriConfig.identifier).toBe("com.rainif.offworkcountdown");
    expect(tauriConfig.bundle.windows.nsis.installerHooks).toBe(
      "./windows/installer-hooks.nsh"
    );
  });

  it("reclaims the old NSIS uninstall key instead of installing a second copy", () => {
    expect(hooks).toContain('!define LEGACY_PRODUCTNAME "Off Work Countdown"');
    expect(hooks).toContain("!macro NSIS_HOOK_PREINSTALL");
    expect(hooks).toContain("!macro NSIS_HOOK_POSTINSTALL");
    expect(hooks).toContain("ReadLegacyInstallDir");
    expect(hooks).toContain("HasCurrentProductInstall");
    expect(hooks).toContain("StrCpy $INSTDIR $R8");
    expect(hooks).toContain("SetOutPath $INSTDIR");
    expect(hooks).toContain('DeleteRegKey SHCTX "${LEGACY_UNINSTKEY}"');
    expect(hooks).toContain(
      '"Software\\${MANUFACTURER}\\${LEGACY_PRODUCTNAME}"'
    );
    expect(hooks).toContain("$SMPROGRAMS\\${LEGACY_PRODUCTNAME}.lnk");
    expect(hooks).toContain("$DESKTOP\\${LEGACY_PRODUCTNAME}.lnk");
    expect(hooks).toContain('CreateShortcut "$DESKTOP\\${PRODUCTNAME}.lnk"');
    expect(hooks).toContain('WriteRegStr HKCU "${RUNKEY}" "${PRODUCTNAME}"');
    expect(hooks).toContain("${MAINBINARYNAME}.exe");
  });
});
