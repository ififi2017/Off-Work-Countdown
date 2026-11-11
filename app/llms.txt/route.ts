import { siteConfig } from "@/config/site";
import { getPublicPages, pageUrl } from "@/features/web-tools/catalog/pages";
import { presets } from "@/lib/presets";

export const dynamic = "force-static";

// llms.txt (https://llmstxt.org): a short Markdown map for AI search and
// answer engines. Preset and salary-tool links come from the same registries
// as the sitemap, so a new page appears here without a second list.
// The web timer runs one start–end shift; rosters are in the mobile apps.

const web = siteConfig.webAppUrl;
const official = siteConfig.officialSiteUrl;

const presetLines = presets.map(
  ({ slug, shift, daysPerWeek }) =>
    `- [${slug}](${web}/en/${slug}): ${shift.start}–${shift.end}, ${daysPerWeek} days a week, ready to run as a countdown`,
);

const toolLines = getPublicPages().map(
  (page) => `- [${page.title}](${pageUrl(page)}): ${page.description}`,
);

const body = `# DoneAt web timer

> The browser version of DoneAt, a work-shift countdown. Set a start time and an end time, including overnight shifts (end earlier than start), and see the time left, a progress bar and an optional earnings estimate. Free, no account, and hours and salary stay in this browser. Formerly Off Work Countdown.

Official site (brand, downloads, FAQ, privacy): ${official}

Key facts:

- Free and open source (MPL-2.0): ${siteConfig.github}
- Works offline after the first visit. Reminders fire only while the tab is open; the iPhone, iPad, Android, Mac and Windows apps can notify after it is closed.
- Share links carry only the start and end times, never salary.
- The web timer runs one start and end time. Rotating shifts, alternating weeks, public holidays and a monthly schedule calendar are in the iPhone, iPad and Android apps: ${official}/en/download
- The countdown, work hours calculator and common-shift pages are available in 19 languages: replace /en with a code such as /zh-CN, /ja or /de. Salary tools are in English (US) and Simplified Chinese (mainland China).

## Tools

- [Countdown timer](${web}/en): remaining time, progress and optional earnings for today's shift
- [Work hours calculator](${web}/en/work-hours-calculator): finish time from a start time, hours and an unpaid break, or how long a shift is
${toolLines.join("\n")}

## Common shifts

${presetLines.join("\n")}

## Optional

- [Official site llms.txt](${official}/llms.txt)
- [FAQ](${official}/en/faq)
- [Sitemap](${web}/sitemap.xml) (do not fetch /sitemap-index.xml; that path is not a sitemap)
`;

export function GET() {
  return new Response(body, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
