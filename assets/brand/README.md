# Off Work Countdown brand mark

The mark is **Open Day**: a clock reading five, whose ring breaks open where the
day ends, with a warm dot that has already left through the break. The workday
has an end; the time after it belongs to the user.

Five o'clock is not decoration — 17:00 is the clock-off time the product
defaults to, so the hands name the moment the countdown is counting to. Cream
hands inside an orange ring is what the previous icon looked like, which is why
people who already have the app still recognise this one.

`off-work-countdown-icon.svg` is the 1024 × 1024 full composition. It has no
rounded mask, border, or baked shadow; each platform owns its final mask and
edge treatment. `off-work-countdown-mark.svg` is the transparent UI mark — the
hands carry the light/dark swap (plum on light, cream on dark), while the ring
and the dot read on both. `off-work-countdown-icon-rounded.svg` is only for
legacy/Web/Desktop surfaces that display the bitmap directly instead of applying
a platform icon mask.

The macOS menu-bar tray uses rasterized marks, not the purple-backed App icon:
`src-tauri/icons/macos-tray-mark.png` (plum hands) and
`macos-tray-mark-dark.png` (cream hands). Render them with sharp — `qlmanage`
composites a transparent SVG onto white. Do not list those files in
`tauri.conf.json` `bundle.icon`, or Windows will pick up the transparent mark
too.

The files in `layers/` are flat, opaque, aligned 1024 × 1024 SVG canvases for
Icon Composer. Import them in numeric order — background, ring, hands, dot —
keep the background full-bleed, and use the ring, the hands and the free-time
dot as separate foreground layers. Appearance color, translucency, specular
highlights, refraction, and shadows belong in Icon Composer rather than in these
source layers.

Every path in this set was authored for this product; no stock icon, SF Symbol,
or third-party artwork is embedded. That improves provenance, but it is not a
substitute for a trademark clearance search before registration or a major
paid campaign.
