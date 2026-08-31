import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  DEFAULT_IOS_STYLE_APP_GROUP,
  iosStyleAppGroupMessage,
  parseAppGroups,
  profileAuthorizesAppGroup,
  resolveMacosAppGroupIdentifier,
} from "./macos-app-group-identifier.mjs";

const TEAM_ID = "3GSK5B9S3T";
const MACOS_APP_GROUP = `${TEAM_ID}.${DEFAULT_IOS_STYLE_APP_GROUP}`;

describe("resolveMacosAppGroupIdentifier", () => {
  it("keeps the iOS-style default for ad-hoc builds without a Team ID", () => {
    expect(
      resolveMacosAppGroupIdentifier({
        identifier: DEFAULT_IOS_STYLE_APP_GROUP,
        teamId: "",
        signingMode: "adhoc",
      })
    ).toBe(DEFAULT_IOS_STYLE_APP_GROUP);
  });

  it("prefixes group.* with the Team ID when one is set", () => {
    expect(
      resolveMacosAppGroupIdentifier({
        identifier: DEFAULT_IOS_STYLE_APP_GROUP,
        teamId: TEAM_ID,
        signingMode: "distribution",
      })
    ).toBe(MACOS_APP_GROUP);
  });

  it("does not double-prefix an identifier that already starts with the Team ID", () => {
    expect(
      resolveMacosAppGroupIdentifier({
        identifier: MACOS_APP_GROUP,
        teamId: TEAM_ID,
        signingMode: "distribution",
      })
    ).toBe(MACOS_APP_GROUP);
  });

  it("rejects store signing without a Team ID", () => {
    expect(() =>
      resolveMacosAppGroupIdentifier({
        identifier: DEFAULT_IOS_STYLE_APP_GROUP,
        teamId: "",
        signingMode: "distribution",
      })
    ).toThrow(/OWC_APPLE_TEAM_ID is required/);
  });

  it("rejects a store identifier that still does not start with the Team ID", () => {
    expect(() =>
      resolveMacosAppGroupIdentifier({
        identifier: "com.example.unprefixed",
        teamId: TEAM_ID,
        signingMode: "automatic",
      })
    ).toThrow(/must start with 3GSK5B9S3T/);
  });

  it("uses the same default group name as build.rs", () => {
    const rust = readFileSync("src-tauri/build.rs", "utf8");
    expect(rust).toContain(`"${DEFAULT_IOS_STYLE_APP_GROUP}"`);
  });
});

describe("Mac App Store App Group guards", () => {
  it("parses both plist XML and codesign textual dumps", () => {
    const xml = `
      <key>com.apple.security.application-groups</key>
      <array>
        <string>${DEFAULT_IOS_STYLE_APP_GROUP}</string>
      </array>
    `;
    const textual = `[Key] com.apple.security.application-groups\n[Array]\n    [String] ${MACOS_APP_GROUP}\n`;
    expect(parseAppGroups(xml)).toEqual([DEFAULT_IOS_STYLE_APP_GROUP]);
    expect(parseAppGroups(textual)).toEqual([MACOS_APP_GROUP]);
  });

  it("does not treat group.* as authorized by a Team ID wildcard", () => {
    // 这就是上次 409 能过本地、过不了商店的原因：描述文件是 3GSK5B9S3T.*，
    // 签名却是 group.com.rainif…。通配只匹配「签进去的那一串」本身。
    expect(
      profileAuthorizesAppGroup(DEFAULT_IOS_STYLE_APP_GROUP, [`${TEAM_ID}.*`])
    ).toBe(false);
    expect(profileAuthorizesAppGroup(MACOS_APP_GROUP, [`${TEAM_ID}.*`])).toBe(
      true
    );
  });

  it("explains the 409 when a signed bundle still carries group.*", () => {
    const message = iosStyleAppGroupMessage([DEFAULT_IOS_STYLE_APP_GROUP], {
      source: "DoneAt.app",
      teamId: TEAM_ID,
    });
    expect(message).toContain("409");
    expect(message).toContain(DEFAULT_IOS_STYLE_APP_GROUP);
    expect(message).toContain(MACOS_APP_GROUP);
  });
});
