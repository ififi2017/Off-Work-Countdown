import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  // iOS is a new platform of the existing paid macOS App Store record, not a
  // separate product. Keep the bundle id aligned for Universal Purchase.
  appId: "com.rainif.offworkcountdown.macappstore",
  appName: "Off Work Countdown",
  webDir: "out",
  loggingBehavior: "debug",
  zoomEnabled: false,
  ios: {
    path: "src-mobile/ios",
    scheme: "App",
    preferredContentMode: "mobile",
  },
};

export default config;
