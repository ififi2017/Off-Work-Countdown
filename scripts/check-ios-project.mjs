import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";

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

try {
  execFileSync(process.execPath, ["scripts/generate-watch-localizations.mjs", "--check"], { stdio: "pipe" });
} catch {
  fail("Watch localization output is stale; run node scripts/generate-watch-localizations.mjs.");
}

const universalBundleId = "com.rainif.offworkcountdown.macappstore";
// One Icon Composer document is the app icon for iPhone, iPad and Watch. It
// lives with the brand sources and is referenced, not copied or symlinked:
// actool cannot read an .icon through a symlink.
const appIconPath = "assets/brand/AppIcon.icon";
let appIconDocument = null;
try {
  appIconDocument = JSON.parse(readFileSync(`${appIconPath}/icon.json`, "utf8"));
} catch {
  fail(`${appIconPath}/icon.json is missing or unreadable.`);
}
const appIconImages = (appIconDocument?.groups ?? [])
  .flatMap((group) => group.layers ?? [])
  .map((layer) => layer["image-name"])
  .filter(Boolean);
if (
  appIconImages.length === 0 ||
  appIconImages.some((name) => !existsSync(`${appIconPath}/Assets/${name}`)) ||
  !appIconDocument?.["supported-platforms"]?.circles?.includes("watchOS")
) {
  fail(`${appIconPath} must list existing layer images and include the watchOS icon.`);
}
for (const catalog of ["src-mobile/ios/App/App/Assets.xcassets", "src-mobile/ios/WatchApp/Assets.xcassets"]) {
  if (existsSync(`${catalog}/AppIcon.appiconset`)) {
    fail(`${catalog}/AppIcon.appiconset is superseded by ${appIconPath}; remove it.`);
  }
}
// Required-reason APIs used by local preferences and the widget snapshot cache.
for (const [path, category, reason] of [
  ["App/Native/PrivacyInfo.xcprivacy", "UserDefaults", "CA92.1"],
  ["WidgetExtension/PrivacyInfo.xcprivacy", "FileTimestamp", "C617.1"],
  ["../WatchApp/PrivacyInfo.xcprivacy", "FileTimestamp", "C617.1"],
  ["../WatchWidgets/PrivacyInfo.xcprivacy", "FileTimestamp", "C617.1"],
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
const appScheme = readFileSync(
  "src-mobile/ios/App/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme",
  "utf8"
);
const watchScheme = readFileSync(
  "src-mobile/ios/App/App.xcodeproj/xcshareddata/xcschemes/DoneAt Watch App.xcscheme",
  "utf8"
);
const watchSource = readFileSync("src-mobile/ios/WatchApp/DoneAtWatchApp.swift", "utf8");
const watchWidgetSource = readFileSync("src-mobile/ios/WatchWidgets/DoneAtWatchWidgets.swift", "utf8");
const watchWidgetInfo = readFileSync("src-mobile/ios/WatchWidgets/Info.plist", "utf8");
const watchEntitlements = readFileSync("src-mobile/ios/WatchApp/WatchApp.entitlements", "utf8");
const watchWidgetEntitlements = readFileSync("src-mobile/ios/WatchWidgets/WatchWidgets.entitlements", "utf8");
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
const bundleIdAssignments = [
  ...iosProject.matchAll(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);/g),
].map((match) => match[1].trim());
const widgetBundleId = `${universalBundleId}.widget`;
const testBundleId = `${universalBundleId}.tests`;
const watchBundleId = `${universalBundleId}.watchkitapp`;
const watchWidgetBundleId = `${watchBundleId}.widgets`;
const watchTestBundleId = `${watchBundleId}.tests`;
const allowedBundleIds = new Set([
  universalBundleId, widgetBundleId, testBundleId,
  watchBundleId, watchWidgetBundleId, watchTestBundleId,
]);
if (
  !bundleIdAssignments.includes(universalBundleId) ||
  !bundleIdAssignments.includes(widgetBundleId) ||
  !bundleIdAssignments.includes(testBundleId) ||
  !bundleIdAssignments.includes(watchBundleId) ||
  !bundleIdAssignments.includes(watchWidgetBundleId) ||
  !bundleIdAssignments.includes(watchTestBundleId) ||
  bundleIdAssignments.some((value) => !allowedBundleIds.has(value))
) {
  fail(
    "The iOS, Watch, Widget, and test targets must keep their assigned Universal Purchase bundle ids."
  );
}
const countProjectText = (needle) => iosProject.split(needle).length - 1;
const watchGroup = `group.${universalBundleId}.watch`;
if (
  !iosProject.includes('name = "DoneAt Watch App"') ||
  !/D10000000000000000000001 \/\* DoneAt Watch App \*\/[\s\S]*?productType = "com\.apple\.product-type\.application"/.test(iosProject) ||
  !iosProject.includes('name = "DoneAt Watch Widgets"') ||
  !iosProject.includes("name = WatchAppTests") ||
  !iosProject.includes("SDKROOT = watchos") ||
  !iosProject.includes("WATCHOS_DEPLOYMENT_TARGET = 26.0") ||
  !iosProject.includes(`INFOPLIST_KEY_WKCompanionAppBundleIdentifier = ${universalBundleId}`) ||
  !/DoneAt Watch App\.app in Embed Watch Content/.test(iosProject) ||
  !/DoneAt Watch Widgets\.appex in Embed Foundation Extensions/.test(iosProject) ||
  countProjectText("WatchSnapshot.swift in Sources") !== 6 ||
  countProjectText("WatchSnapshotCache.swift in Sources") !== 6 ||
  countProjectText("WatchPairing.swift in Sources") !== 6 ||
  countProjectText("WatchDisplayProjection.swift in Sources") !== 6 ||
  countProjectText("WatchLocalizations.generated.swift in Sources") !== 4 ||
  countProjectText("WatchShiftEvaluation.swift in Sources") !== 6 ||
  // WatchAppTests is an explicit-reference target: a test file on disk but not
  // in its Sources phase never runs, and the Watch test scheme stays green.
  countProjectText("WatchDisplayProjectionTests.swift in Sources") !== 2 ||
  countProjectText("WatchSnapshotReceiverTests.swift in Sources") !== 2
) {
  fail("The Watch app must keep its Xcode 26 companion, Widget, test, embed, and shared-contract target graph.");
}
if (
  // Xcode rewrites shared schemes as `BlueprintName = "…"` when the project is
  // opened, so match the attribute rather than one spelling of its whitespace.
  !/BlueprintName\s*=\s*"DoneAt Watch App"/.test(watchScheme) ||
  !/BlueprintName\s*=\s*"WatchAppTests"/.test(watchScheme) ||
  !watchWidgetInfo.includes("com.apple.widgetkit-extension") ||
  !watchWidgetInfo.includes("$(PRODUCT_BUNDLE_IDENTIFIER)") ||
  !watchWidgetInfo.includes("$(EXECUTABLE_NAME)") ||
  !watchWidgetInfo.includes("$(MARKETING_VERSION)") ||
  !watchWidgetInfo.includes("$(CURRENT_PROJECT_VERSION)") ||
  !watchWidgetInfo.includes("<string>XPC!</string>") ||
  !iosProject.includes("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon") ||
  !watchSource.includes("WatchSnapshotReceiver") ||
  !watchWidgetSource.includes(".accessoryCircular") ||
  !watchWidgetSource.includes(".accessoryRectangular") ||
  /ControlWidget|AppIntent|Button\s*\(/.test(watchWidgetSource) ||
  !watchSource.includes("@main")
) {
  fail("The shared Watch scheme and read-only circular/rectangular Widget entry points must remain minimal.");
}
if (/\b(?:UIKit|CloudKit|JavaScriptCore)\b|\bsalary\b|\bcommandId\b|\bACK\b/.test(
  `${watchSource}\n${watchWidgetSource}`
)) {
  fail("The W0 Watch targets must remain read-only and independent of iPhone stores, JSCore, salary, and control protocols.");
}
if (
  !watchEntitlements.includes(watchGroup) ||
  !watchWidgetEntitlements.includes(watchGroup) ||
  watchEntitlements.includes(`<string>group.${universalBundleId}</string>`) ||
  watchWidgetEntitlements.includes(`<string>group.${universalBundleId}</string>`)
) {
  fail(`The Watch app and its Widget must share only ${watchGroup}.`);
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
// Parse each Release XCBuildConfiguration by its settings, not its line layout:
// Xcode rewrites hand-added one-line configurations as multi-line blocks when
// the project is open, and both spellings must validate the same way.
const releaseConfigurations = [
  ...iosProject.matchAll(
    /isa = XCBuildConfiguration;\s*buildSettings = \{([^{}]*)\};\s*name = Release;/g
  ),
].map((match) => match[1]);
const shippingReleaseConfigurations = releaseConfigurations.filter((settings) =>
  /PRODUCT_BUNDLE_IDENTIFIER = com\.rainif\.offworkcountdown\.macappstore(?:\.widget|\.watchkitapp|\.watchkitapp\.widgets)?;/.test(
    settings
  )
);
if (
  // The project itself plus App, Widget, AppTests, Watch App, Watch Widgets, WatchAppTests.
  releaseConfigurations.length !== 7 ||
  releaseConfigurations.some(
    (settings) =>
      settings.includes("-DDEBUG") ||
      /SWIFT_ACTIVE_COMPILATION_CONDITIONS = [^;]*\bDEBUG\b/.test(settings)
  ) ||
  shippingReleaseConfigurations.length !== 4 ||
  shippingReleaseConfigurations.some(
    (settings) => !settings.includes('SWIFT_ACTIVE_COMPILATION_CONDITIONS = "";')
  )
) {
  fail("Every iOS Release configuration must compile without the DEBUG condition.");
}
if (
  (statSync(xcodeCloudScriptPath).mode & 0o111) === 0 ||
  !xcodeCloudScript.startsWith("#!/bin/sh") ||
  !xcodeCloudScript.includes("npm ci") ||
  !xcodeCloudScript.includes("npm run check:ios-rule-fixtures") ||
  !xcodeCloudScript.includes("npm run check:ios")
) {
  fail("Xcode Cloud must install dependencies, check the rule fixtures and validate iOS before building.");
}
// Plan 019 R4 removed the JavaScriptCore rules bundle. The Swift port is the
// only implementation; a resurrected bundle would be a second one.
if (/CountdownRules\.js/.test(iosProject) || existsSync("src-mobile/ios/App/App/Resources/CountdownRules.js")) {
  fail("CountdownRules.js was removed in plan 019 R4; iOS rules live in Swift.");
}
// Plan 019 §3: the app's copy ships as a String Catalog. The public/locales
// folder reference went with it — leaving it behind would put 19 JSON files
// back in the bundle and make it ambiguous which one the app actually reads.
if (!existsSync("src-mobile/ios/App/App/Localizable.xcstrings")) {
  fail("Localizable.xcstrings is missing; run node scripts/generate-ios-xcstrings.mjs.");
}
if (!/Localizable\.xcstrings in Resources/.test(iosProject)) {
  fail("Localizable.xcstrings must be copied into the App resources.");
}
if (/\/\* locales \*\//.test(iosProject)) {
  fail("public/locales is no longer bundled into iOS; the app reads Localizable.xcstrings.");
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
  !/@main\s+(?:@MainActor\s+)?struct\s+\w+\s*:\s*App\s*\{/.test(appDelegate) ||
  !/WindowGroup\s*\{/.test(appDelegate) ||
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
  !widgetInfo.includes("com.apple.widgetkit-extension") ||
  !widgetSource.includes("ActivityConfiguration") ||
  !widgetSource.includes("OffWorkCountdownWidget") ||
  // Xcode renamed this copy-files phase from "Embed App Extensions" to
  // "Embed Foundation Extensions" and rewrites it on open. The phase is
  // otherwise identical — same UUIDs, same dstSubfolderSpec 13 — so match
  // either name rather than pinning the label Xcode happens to use today.
  !/OffWorkCountdownWidgetsExtension\.appex in Embed \w+ Extensions/.test(iosProject)
) {
  fail("The native iOS target must keep its embedded Widget and Live Activity surfaces.");
}
const appGroup = `group.${universalBundleId}`;
if (
  !appEntitlements.includes(appGroup) ||
  !widgetEntitlements.includes(appGroup)
) {
  fail(`The App and Widget must share ${appGroup}.`);
}
// Xcode may re-quote or reorder attributes when it saves, so match the
// reference by meaning: one AppIcon.icon file, built into both apps.
const appIconReference = iosProject.match(
  /(\w{24}) \/\* AppIcon\.icon \*\/ = \{isa = PBXFileReference;[^}]*\bpath = "?\.\.\/\.\.\/\.\.\/assets\/brand\/AppIcon\.icon"?;/
);
const appIconBuildFiles = appIconReference
  ? [...iosProject.matchAll(new RegExp(`(\\w{24}) \\/\\* AppIcon\\.icon in Resources \\*\\/ = \\{isa = PBXBuildFile; fileRef = ${appIconReference[1]}\\b`, "g"))]
      .map((match) => match[1])
  : [];
const resourcePhases = [...iosProject.matchAll(/isa = PBXResourcesBuildPhase;[^}]*files = \(([^)]*)\)/g)].map((match) => match[1]);
if (
  !appIconReference ||
  appIconBuildFiles.length !== 2 ||
  appIconBuildFiles.some((id) => resourcePhases.filter((files) => files.includes(id)).length !== 1)
) {
  fail("AppIcon.icon must be referenced from assets/brand and copied into the App and Watch App resources.");
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
  !sharedWidgetSource.includes('private func widgetProductName(locale: String) -> String {\n    "DoneAt"')
) {
  fail("Every iOS outer surface and the shared widget must use the DoneAt short name.");
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
  "The production SwiftUI project keeps its iPhone/iPad, WidgetKit, ActivityKit, and read-only Watch target graph."
);
