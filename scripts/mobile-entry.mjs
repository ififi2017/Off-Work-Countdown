function escapeJsonForInlineScript(value) {
  return JSON.stringify(value).replaceAll("<", "\\u003c");
}

export function createMobileEntryHtml({
  locales,
  defaultLocale,
  languageMapping,
  preferredLanguageStorageKey,
}) {
  const localeList = [...locales];
  const localeLookup = Object.fromEntries(
    localeList.map((locale) => [locale.toLowerCase(), locale])
  );
  const languageLookup = Object.fromEntries(
    Object.entries(languageMapping).map(([source, target]) => [
      source.toLowerCase(),
      target,
    ])
  );

  return `<!doctype html>
<html lang="${defaultLocale}" data-build-target="mobile">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="color-scheme" content="light dark">
    <title>DoneAt</title>
    <style>
      html,body{height:100%;margin:0}body{display:grid;place-items:center;background:#f3f4f6;color:#374151;font:14px system-ui,-apple-system,sans-serif}span{opacity:.72}@media(prefers-color-scheme:dark){body{background:#111827;color:#e5e7eb}}
    </style>
  </head>
  <body>
    <span role="status" aria-live="polite">Opening…</span>
    <noscript><a href="${defaultLocale}.html">Open DoneAt</a></noscript>
    <script>
      (function () {
        var locales = ${escapeJsonForInlineScript(localeLookup)};
        var mappings = ${escapeJsonForInlineScript(languageLookup)};
        var fallback = ${escapeJsonForInlineScript(defaultLocale)};

        function resolveLocale(value) {
          if (!value) return null;
          var normalized = String(value).replace(/_/g, "-").toLowerCase();
          if (locales[normalized]) return locales[normalized];
          if (mappings[normalized]) return mappings[normalized];
          var base = normalized.split("-")[0];
          return locales[base] || mappings[base] || null;
        }

        var candidates = [];
        try {
          candidates.push(localStorage.getItem(${escapeJsonForInlineScript(preferredLanguageStorageKey)}));
          candidates.push(localStorage.getItem("i18nextLng"));
        } catch (_) {}
        if (navigator.languages) candidates.push.apply(candidates, navigator.languages);
        candidates.push(navigator.language);

        var locale = fallback;
        for (var i = 0; i < candidates.length; i += 1) {
          var resolved = resolveLocale(candidates[i]);
          if (resolved) { locale = resolved; break; }
        }
        location.replace(new URL(locale + ".html", location.href).href);
      })();
    </script>
  </body>
</html>
`;
}
