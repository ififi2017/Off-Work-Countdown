import { existsSync, readFileSync } from "node:fs";

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
const widgetEntitlements = readFileSync(
  "src-mobile/ios/App/WidgetExtension/Widget.entitlements",
  "utf8"
);
const appIcon = readFileSync(
  "src-mobile/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
);
const bundleIdAssignments = [
  ...iosProject.matchAll(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);/g),
].map((match) => match[1].trim());
const widgetBundleId = `${universalBundleId}.widget`;
if (
  !bundleIdAssignments.includes(universalBundleId) ||
  !bundleIdAssignments.includes(widgetBundleId) ||
  bundleIdAssignments.some(
    (value) => value !== universalBundleId && value !== widgetBundleId
  )
) {
  fail(
    `iOS bundle ids must use ${universalBundleId} for the App and ${widgetBundleId} for its Widget extension.`
  );
}
if (
  !appDelegate.includes("import SwiftUI") ||
  !appDelegate.includes("OffWorkCountdownRootView()") ||
  iosProject.includes("MobileBridgeViewController.swift in Sources")
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
  !iosProject.includes("OffWorkCountdownWidgetsExtension.appex in Embed App Extensions")
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
for (const suffix of ["", "-1", "-2"]) {
  if (
    !existsSync(
      `src-mobile/ios/App/App/Assets.xcassets/Splash.imageset/splash-dark-2732x2732${suffix}.png`
    )
  ) {
    fail("The iOS Launch Screen must include dark appearance assets.");
  }
}

console.log(
  "The production SwiftUI target supports iPhone/iPad, WidgetKit, ActivityKit and Universal Purchase."
);
