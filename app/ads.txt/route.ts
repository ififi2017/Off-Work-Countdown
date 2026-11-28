import { ADSENSE_CLIENT_ID } from "@/lib/ads";

export const dynamic = "force-static";

// AdSense ads.txt for the browser site. Same publisher as lib/ads.ts and
// rainif.com/ads.txt. A route, not a [lang] page: middleware skips dotted
// paths, and rendering "ads.txt" as a locale throws inside Intl.NumberFormat.
const ADS_TXT = `google.com, ${ADSENSE_CLIENT_ID.replace(/^ca-/, "")}, DIRECT, f08c47fec0942fa0\n`;

export function GET() {
  return new Response(ADS_TXT, {
    headers: {
      "Content-Type": "text/plain",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
