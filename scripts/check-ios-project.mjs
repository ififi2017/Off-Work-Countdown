import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";

// Guards the native iOS project's shipping configuration.
//
// Deliberately independent of any Next.js build: iOS stopped consuming a Web
// export when it became a SwiftUI app, and the two were only ever coupled
// because this used to live inside the Mobile build check. It reads the Xcode
// project and its resources straight from the working tree, so it runs on a
// clean clone without building anything.
//
// This is currently the only automated guard on the iOS target — there is no
// iOS job in CI. Run it whenever src-mobile/ios changes.

function fail(message) {
  console.error(message);
  process.exit(1);
}

const universalBundleId = "com.rainif.offworkcountdown.macappstore";
// Required-reason APIs used by local preferences and the widget snapshot cache.
for (const [path, category, reason] of [
  ["App/Native/PrivacyInfo.xcprivacy", "UserDefaults", "CA92.1"],
  ["WidgetExtension/PrivacyInfo.xcprivacy", "FileTimestamp", "C617.1"],
]) {
  const manifestPath = `src-mobile/ios/App/${path}`;
  if (!existsSync(manifestPath)) fail(`Missing privacy manifest: ${manifestPath}`);
  const manifest = readFileSync(manifestPath, "utf8");
  if (!manifest.includes(`<string>NSPrivacyAccessedAPICategory${category}</string>`)
      || !manifest.includes(`<string>${reason}</string>`)) {
    fail(`Privacy manifest must declare ${category} / ${reason}: ${manifestPath}`);
  }
}
const iosProject = readFileSync(
  "src-mobile/ios/App/App.xcodeproj/project.pbxproj",
  "utf8"
);
const iosInfo = readFileSync("src-mobile/ios/App/App/Info.plist", "utf8");
const appDelegate = readFileSync(
  "src-mobile/ios/App/App/AppDelegate.swift",
  "utf8"
);
const rootView = readFileSync(
  "src-mobile/ios/App/App/Native/Views/RootView.swift",
  "utf8"
);
const appScheme = readFileSync(
  "src-mobile/ios/App/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme",
  "utf8"
);
const plusEntitlementSource = readFileSync(
  "src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift",
  "utf8"
);
const storeKitConfigurationPath =
  "src-mobile/ios/App/DoneAtConnect.storekit";
const storeKitConfigurationIdentifier = "../../DoneAtConnect.storekit";
const appEntitlements = readFileSync(
  "src-mobile/ios/App/App/App.entitlements",
  "utf8"
);
const widgetInfo = readFileSync(
  "src-mobile/ios/App/WidgetExtension/Info.plist",
  "utf8"
);
const widgetSource = readFileSync(
  "src-mobile/ios/App/WidgetExtension/OffWorkWidgets.swift",
  "utf8"
);
const iosBrandSource = readFileSync(
  "src-mobile/ios/App/App/Native/DesignSystem/OWCDesignSystem.swift",
  "utf8"
);
const sharedWidgetSource = readFileSync(
  "src-tauri/macos-widget/Sources/OffWorkCountdownWidgetUI/OffWorkCountdownWidget.swift",
  "utf8"
);
const widgetEntitlements = readFileSync(
  "src-mobile/ios/App/WidgetExtension/Widget.entitlements",
  "utf8"
);
const xcodeCloudScriptPath =
  "src-mobile/ios/App/ci_scripts/ci_post_clone.sh";
const xcodeCloudScript = readFileSync(xcodeCloudScriptPath, "utf8");
const appIcon = readFileSync(
  "src-mobile/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
);
const bundleIdAssignments = [
  ...iosProject.matchAll(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);/g),
].map((match) => match[1].trim());
const widgetBundleId = `${universalBundleId}.widget`;
const testBundleId = `${universalBundleId}.tests`;
if (
  !bundleIdAssignments.includes(universalBundleId) ||
  !bundleIdAssignments.includes(widgetBundleId) ||
  !bundleIdAssignments.includes(testBundleId) ||
  bundleIdAssignments.some(
    (value) =>
      value !== universalBundleId &&
      value !== widgetBundleId &&
      value !== testBundleId
  )
) {
  fail(
    `iOS bundle ids must use ${universalBundleId} for the App and ${widgetBundleId} for its Widget extension.`
  );
}
if (
  !appScheme.includes('<ArchiveAction\n      buildConfiguration = "Release"') ||
  !appScheme.includes('buildForArchiving = "YES"')
) {
  fail("The shared App scheme must archive the application with the Release configuration.");
}
if (
  !existsSync(storeKitConfigurationPath) ||
  !appScheme.includes(`identifier = "${storeKitConfigurationIdentifier}"`)
) {
  fail(
    "The shared App scheme must use the App Store Connect-synced StoreKit configuration."
  );
}
const storeKitConfiguration = JSON.parse(
  readFileSync(storeKitConfigurationPath, "utf8")
);
const expectedStoreKitProductIds = [
  "com.rainif.offworkcountdown.plus.lifetime",
  "com.rainif.offworkcountdown.plus.monthly",
  "com.rainif.offworkcountdown.plus.yearly",
];
const storeKitProductIds = [
  ...(storeKitConfiguration.products ?? []).map((product) => product.productID),
  ...(storeKitConfiguration.subscriptionGroups ?? []).flatMap((group) =>
    (group.subscriptions ?? []).map((subscription) => subscription.productID)
  ),
].sort();
const storeKitSubscriptionGroupIds = [
  ...(storeKitConfiguration.subscriptionGroups ?? []).flatMap((group) =>
    (group.subscriptions ?? []).map(
      (subscription) => subscription.subscriptionGroupID
    )
  ),
];
if (
  !storeKitConfiguration.settings?._applicationInternalID ||
  !storeKitConfiguration.settings?._developerTeamID ||
  JSON.stringify(storeKitProductIds) !==
    JSON.stringify(expectedStoreKitProductIds.sort()) ||
  !storeKitSubscriptionGroupIds.length ||
  storeKitSubscriptionGroupIds.some((groupID) => groupID !== "22345761") ||
  !plusEntitlementSource.includes(
    'static let storeKitConfigurationGroupID = "22345761"'
  ) ||
  iosProject.includes("DoneAtConnect.storekit in Resources")
) {
  fail(
    "The StoreKit configuration must stay synced with App Store Connect and out of shipping app resources."
  );
}
const releaseConfigurations = [
  ...iosProject.matchAll(
    /\/\* Release \*\/ = \{[\s\S]*?buildSettings = \{([\s\S]*?)\n\s*\};\n\s*name = Release;/g
  ),
].map((match) => match[1]);
if (
  releaseConfigurations.length !== 4 ||
  releaseConfigurations.some((settings) => settings.includes("-DDEBUG")) ||
  releaseConfigurations.filter((settings) =>
    settings.includes('SWIFT_ACTIVE_COMPILATION_CONDITIONS = "";')
  ).length !== 2
) {
  fail("Every iOS Release configuration must compile without the DEBUG condition.");
}
if (
  (statSync(xcodeCloudScriptPath).mode & 0o111) === 0 ||
  !xcodeCloudScript.startsWith("#!/bin/sh") ||
  !xcodeCloudScript.includes("npm ci") ||
  !xcodeCloudScript.includes("npm run build:ios-native-rules") ||
  !xcodeCloudScript.includes("npm run check:ios")
) {
  fail("Xcode Cloud must install dependencies, generate native rules and validate iOS before building.");
}
// App/Native is a synchronized folder, so a file that lands there is compiled
// without ever appearing in project.pbxproj. Scanning the directory keeps this
// guard honest; the pbxproj check still covers an explicit reference elsewhere.
const nativeSources = [];
const walkNative = (dir) => {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const child = `${dir}/${entry.name}`;
    if (entry.isDirectory()) walkNative(child);
    else nativeSources.push(entry.name);
  }
};
walkNative("src-mobile/ios/App/App/Native");

if (
  !appDelegate.includes("import SwiftUI") ||
  !appDelegate.includes("OffWorkCountdownRootView()") ||
  iosProject.includes("MobileBridgeViewController.swift in Sources") ||
  nativeSources.includes("MobileBridgeViewController.swift")
) {
  fail("The release iOS target must boot the SwiftUI root without compiling the archived Capacitor controller.");
}
if (!iosProject.includes('TARGETED_DEVICE_FAMILY = "1,2";')) {
  fail("The release iOS target and Widget extension must support iPhone and iPad.");
}
if (
  !iosInfo.includes("UISupportedInterfaceOrientations") ||
  !iosInfo.includes("UIInterfaceOrientationPortrait") ||
  !iosInfo.includes("UIInterfaceOrientationLandscapeLeft") ||
  !iosInfo.includes("UISupportedInterfaceOrientations~ipad") ||
  !iosInfo.includes("NSSupportsLiveActivities")
) {
  fail("The native iOS target must declare iPhone/iPad orientations and Live Activity support.");
}
if (
  !rootView.includes("TabletShellView") ||
  !rootView.includes("PhoneLandscapeShellView") ||
  !rootView.includes("WidgetSnapshotPublisher") ||
  !widgetInfo.includes("com.apple.widgetkit-extension") ||
  !widgetSource.includes("ActivityConfiguration") ||
  !widgetSource.includes("OffWorkCountdownWidget") ||
  // Xcode renamed this copy-files phase from "Embed App Extensions" to
  // "Embed Foundation Extensions" and rewrites it on open. The phase is
  // otherwise identical — same UUIDs, same dstSubfolderSpec 13 — so match
  // either name rather than pinning the label Xcode happens to use today.
  !/OffWorkCountdownWidgetsExtension\.appex in Embed \w+ Extensions/.test(iosProject)
) {
  fail("The native iOS target must keep its adaptive SwiftUI shell, embedded Widget and Live Activity surfaces.");
}
const appGroup = `group.${universalBundleId}`;
if (
  !appEntitlements.includes(appGroup) ||
  !widgetEntitlements.includes(appGroup)
) {
  fail(`The App and Widget must share ${appGroup}.`);
}
const iconWidth = appIcon.readUInt32BE(16);
const iconHeight = appIcon.readUInt32BE(20);
const iconColorType = appIcon[25];
if (
  iconWidth !== 1024 ||
  iconHeight !== 1024 ||
  iconColorType === 4 ||
  iconColorType === 6
) {
  fail("The Universal Purchase App Icon must be a 1024x1024 PNG without alpha.");
}
// The launch screen uses the same background-free mark as WidgetKit. Its
// luminosity appearance keeps the clock hand legible on both system
// backgrounds without putting a second rounded app-icon tile inside the page.
const launchScreen = readFileSync(
  "src-mobile/ios/App/App/Base.lproj/LaunchScreen.storyboard",
  "utf8"
);
if (
  launchScreen.includes('image="BrandIcon"') ||
  launchScreen.includes('image="LaunchMark"') ||
  launchScreen.includes('image="LaunchMarkLight"') ||
  launchScreen.includes('image="LaunchMarkDark"')
) {
  fail(
    "The iOS Launch Screen must draw BrandMark, not a backed app icon or a trait-hidden pair."
  );
}
if (!launchScreen.includes('image="BrandMark"')) {
  fail("The iOS Launch Screen must include BrandMark.");
}
if (!launchScreen.includes('text="DoneAt"') || launchScreen.includes("Off Work Countdown")) {
  fail("The iOS Launch Screen must show only the DoneAt short name, without an English subtitle.");
}
if (
  !iosInfo.includes("<key>CFBundleDisplayName</key>\n\t<string>DoneAt</string>") ||
  !iosInfo.includes("<key>CFBundleName</key>\n\t<string>DoneAt</string>") ||
  !widgetInfo.includes("<key>CFBundleDisplayName</key>\n\t<string>DoneAt</string>") ||
  !widgetInfo.includes("<key>CFBundleName</key>\n\t<string>DoneAt</string>") ||
  !iosBrandSource.includes('static let shortName = "DoneAt"') ||
  !sharedWidgetSource.includes('#if os(iOS)\n    "DoneAt"')
) {
  fail("Every iOS outer surface must use the DoneAt short name without renaming the macOS product.");
}
if (
  !sharedWidgetSource.includes("systemExtraLargePortraitRawValue") ||
  !sharedWidgetSource.includes("extraLargePortraitContent")
) {
  fail(
    "The iOS widget must declare the iOS 27 4×6 portrait XL family and give it a stacked layout distinct from iPad landscape XL."
  );
}
const localizedInfoNames = readdirSync("src-mobile/ios/App/App")
  .filter((entry) => entry.endsWith(".lproj"))
  .map((entry) => `src-mobile/ios/App/App/${entry}/InfoPlist.strings`)
  .filter(existsSync);
if (
  localizedInfoNames.length !== 19 ||
  localizedInfoNames.some((path) => {
    const strings = readFileSync(path, "utf8");
    return !strings.includes('"CFBundleDisplayName" = "DoneAt";') ||
      !strings.includes('"CFBundleName" = "DoneAt";');
  })
) {
  fail("All 19 iOS InfoPlist localizations must expose DoneAt on the Home Screen.");
}
const brandMark = JSON.parse(
  readFileSync(
    "src-mobile/ios/App/App/Assets.xcassets/BrandMark.imageset/Contents.json",
    "utf8"
  )
);
if (
  !brandMark.images.some((image) =>
    (image.appearances ?? []).some(
      (appearance) =>
        appearance.appearance === "luminosity" && appearance.value === "dark"
    )
  )
) {
  fail("BrandMark must keep a dark appearance for WidgetKit and Live Activities.");
}
const appAssetEntries = readdirSync(
  "src-mobile/ios/App/App/Assets.xcassets"
);
if (appAssetEntries.some((entry) => /^Mood-.*\.imageset$/.test(entry))) {
  fail(
    "The native iOS target must render share moods with the system emoji font instead of bundling mood artwork."
  );
}

console.log(
  "The production SwiftUI target supports iPhone/iPad, WidgetKit, ActivityKit and Universal Purchase."
);
