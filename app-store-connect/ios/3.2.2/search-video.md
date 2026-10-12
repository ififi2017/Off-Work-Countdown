# iOS 3.2.2 · Search-results video (local, not uploaded)

ASC slot: Product page → Header and search results → search results asset
(`APP_STORE_SEARCH_RESULTS_ASSET`). 3.2.1 shipped search V4; this replaces it
for 3.2.2 because Records and Time off were redesigned.

## What changed from 3.2.1 V4

- Eight beats of three seconds, cut in 0.3 s, so a viewer gets about three
  seconds of each before the next: countdown → widget → focus → records →
  cycle report → time off → Apple Watch → life. The countdown is on screen,
  ticking, from the first frame.
- Each beat is one headline and one native hero. No wordmark, eyebrow,
  subline or progress dots; "Illustrative data" sits small in the corner, with
  "DoneAt Plus" added on the focus and cycle-report beats.
- Headlines live in `scripts/marketing-shots/ios/creative-copy-3.2.2.mjs`:
  reviewed 3.2.1 V4 tour lines where they still fit the scene, lines written
  for 3.2.2 elsewhere (✎ in the table below).
- Recaptured from one 3.2.2 Debug build (`origin/main` 963c4922 plus two
  Debug-only hooks: `qaLeaveFrom` and the Watch fixture's `workday` state).
  Apple Watch is recorded on a Watch simulator from the Watch app's review
  fixture in its `workday` state: the iPhone review day (09:00–12:00,
  13:00–17:00) in a minute-offset time zone where it is 14:22 at launch, so it
  shows the iPhone's 2:37 left, 62.4 % and off at 17:00, with the phone's own
  `widgetWorking` string as its state label. It is cropped below the status
  bar, whose clock cannot be overridden.
- Layout follows the Art Safe Area of Apple's search template
  (`apple-creative-template-guides.json`, 1920-scale `418,382.5,1084×515`).
  Headline and hero stay inside it; the native surface around each hero
  bleeds past it so the full 3:2 frame reads as full. Heroes are native
  pixels at or below capture resolution; Records, Leave, Focus and the report
  fill the safe-area width, the Watch shows at its native 1:1.
- Time off opens on the plan's cost and result (5 days of leave → 9 days off
  in a row), with both calendar rows of the run below.
- Records: month header joined to last week (regular days, overtime on two
  days, a day of leave shown as a day off, weekend rest); recorded days fill
  in order. Time off: both rows of the nine-day run with its label; each day
  lights up in order. Report: the month's hours counting up live.
- Demo data is identical in every language: no holiday region (so no
  truncated holiday names) and Monday-first weeks (the app's week-start
  setting), which keep the Saturday–Sunday run on two rows.
- Shift alarms was tried for the last beat and dropped: without a configured
  alarm the screen is a single "off" toggle and does not read in three seconds.

## Headlines

✎ written for 3.2.2 (needs review); everything else is the reviewed 3.2.1
copy. Records was rewritten for most locales because the V4 line described
the year view in colour, and for ja/ko/zh-TW because it opened the same way as
the cycle-report line. Korean Watch repeated the countdown line. Other ✎
lines replace V4 lines too long to set at a readable size.

All eight headlines in a video share one size, the largest at which every
line fits on one line: 64 px floor for Latin, Cyrillic, Thai, Devanagari and
Arabic, 68 px for CJK; 56 px is the hard audit limit. Sizes per locale are in
the manifest (`headlineSize`, `headlineFits`).

| Locale | Countdown | Widget | Focus | Records | Cycle report | Time off | Apple Watch | Life |
|---|---|---|---|---|---|---|---|---|
| mr-IN | प्रत्येक सेकंद. तुमच्या वेळेच्या जवळ. | ॲप न उघडताही, किती वेळ उरला. | लक्ष द्या. मग थोडा विराम. | तुमचे दिवस. एका नजरेत. ✎ | कामाचे दिवस, अधिक स्पष्ट. | थोडी रजा. मोठा विराम. | मनगट उचला. किती वेळ उरला, पाहा. | काम, आयुष्याच्या मोठ्या चित्रात. ✎ |
| zh-CN | 几点下班， 一眼有数。 | 不用打开， 也能看见。 | 把这一段， 留给专注。 | 时间去哪， 都有迹可循。 | 忙过的日子， 慢慢看清。 | 一点请假， 多一点假期。 | 抬腕， 离下班更近。 | 把工作， 放回人生里。 ✎ |
| zh-TW | 幾點下班， 一眼有數。 | 不打開， 也看得到。 | 專心一會兒， 再歇一會兒。 | 時間去哪， 都有跡可循。 ✎ | 忙過的日子， 慢慢看清。 | 把假期， 排得更完整。 | 抬起手腕， 下班更近了。 | 把工作， 放回人生裡。 ✎ |
| en | Know when you’re done. ✎ | A glance. And you know. | One thing. Your full focus. | Your days. In perspective. | Your month, in review. ✎ | A little leave. A longer break. | On your wrist. Closer to done. ✎ | Work, in the bigger picture. ✎ |
| de | Jede Sekunde. Näher am Feierabend. | Auch ohne Öffnen der App. | Zeit für Fokus. Zeit für Pausen. | Deine Tage. Im Überblick. ✎ | Deine Arbeitstage. Klarer im Blick. | Wenige Urlaubstage. Mehr freie Zeit. | Ein Blick. Bald Feierabend. | Die Arbeit, im großen Ganzen. ✎ |
| fr | Voyez quand vous finissez. ✎ | Même sans ouvrir l’app. | Se concentrer. Puis souffler. | Vos journées. En perspective. ✎ | Votre mois. Plus clair. ✎ | Quelques congés. Une vraie pause. | Un regard. Bientôt libre. | Le travail, à sa juste place. ✎ |
| es | Cada segundo. Más cerca de salir. | Sin abrir la app. | Concéntrate. Luego, descansa. ✎ | Tus días. En perspectiva. ✎ | Tus días de trabajo. Todo más claro. | Poco permiso. Más descanso. ✎ | Mira tu muñeca. Ya queda menos. | El trabajo, en su justa medida. ✎ |
| it | Ogni secondo. Più vicino alla fine. | Anche senza aprire l’app. | Concentrati. Poi fai una pausa. | I tuoi giorni. In prospettiva. ✎ | Il tuo mese, più chiaro. ✎ | Poche ferie. Pause più lunghe. ✎ | Uno sguardo. Manca meno. | Il lavoro, nel quadro della vita. ✎ |
| pt | Cada segundo. Mais perto de sair. | Sem abrir o app. | Hora de focar. Hora de pausar. | Seus dias. Em perspectiva. ✎ | Seu mês, mais claro. ✎ | Pouca folga. Pausa maior. ✎ | Olhe o pulso. Falta menos. | O trabalho, no quadro da vida. ✎ |
| ja | 一秒ずつ。 自分の時間へ。 | 開かなくても、 あと何分。 | 集中する時間。 ひと息つく時間。 | 毎日の記録が、 ひと目でわかる。 ✎ | 働いた日々を、 ゆっくり見渡す。 | 少しの休暇で、 長めのひと休み。 | 手首を見る。 退勤が近づく。 | 仕事を、 人生の中で見る。 ✎ |
| ko | 매초마다. 퇴근이 가까워져요. | 앱을 열지 않아도, 한눈에. ✎ | 집중할 시간. 쉬어 갈 시간. | 하루하루가, 한눈에. ✎ | 일한 날들을, 더 또렷하게. | 휴가를 조금 더해, 더 긴 쉼으로. | 손목을 들면, 남은 시간이 보여요. ✎ | 일을, 삶 속에서 바라봐요. ✎ |
| ru | Всё ближе к концу смены. ✎ | Без запуска приложения. | Работа. Потом отдых. ✎ | Ваши дни. Как на ладони. ✎ | Рабочие дни. Ясная картина. | Мало отпуска. Много отдыха. ✎ | Взгляд на часы. Скоро домой. | Работа — часть большой жизни. ✎ |
| tr | Her saniye, mesai sonuna. ✎ | Uygulamayı açmadan da gör. | Odaklan. Sonra mola ver. | Günlerin. Bir bakışta. ✎ | Çalıştığın günler. Daha net bir bakış. | Biraz izin. Daha uzun bir mola. | Bileğine bak. Az kaldı. | İşini, hayatın içinde gör. ✎ |
| id | Tiap detik, makin dekat pulang. ✎ | Tanpa membuka aplikasi. | Saatnya fokus. Saatnya jeda. | Hari-harimu. Sekilas terlihat. ✎ | Bulanmu, lebih jelas. ✎ | Sedikit cuti. Libur lebih panjang. | Lihat pergelangan. Sebentar lagi. | Pekerjaan, dalam gambaran hidup. ✎ |
| vi | Mỗi giây. Gần giờ tan ca hơn. | Không cần mở ứng dụng. | Lúc tập trung. Lúc nghỉ ngơi. | Từng ngày, thật rõ. ✎ | Tháng của bạn, rõ ràng hơn. ✎ | Nghỉ phép ít, nghỉ ngơi nhiều. ✎ | Nhìn cổ tay. Sắp tan làm. | Công việc, trong cả cuộc đời. ✎ |
| th | ทุกวินาที ใกล้เวลาเลิกงานอีกนิด | ไม่ต้องเปิดแอป ก็ดูได้ | เวลาจดจ่อ เวลาพัก | วันทำงานของคุณ ในแวบเดียว ✎ | มองวันทำงาน ได้ชัดเจนขึ้น | ลาเพิ่มอีกนิด พักได้นานขึ้น | ดูที่ข้อมือ ใกล้เลิกงานแล้ว | งาน ในภาพใหญ่ของชีวิต ✎ |
| hi-IN | हर सेकंड। छुट्टी के और करीब। | ऐप खोले बिना भी देखें। | ध्यान लगाने का वक़्त। फिर थोड़ा आराम। | आपके दिन। एक नज़र में। ✎ | काम के दिन। एक साफ़ तस्वीर। | थोड़ी-सी छुट्टी। थोड़ा लंबा आराम। | कलाई पर देखें। छुट्टी करीब है। | काम, ज़िंदगी की बड़ी तस्वीर में। ✎ |
| ar | كل ثانية. تقترب نهاية دوامك. | دون فتح التطبيق. | وقت للتركيز. ووقت للراحة. | أيامك. في لمحة. ✎ | أيام عملك. صورة أوضح. | إجازة قصيرة. راحة أطول. | نظرة لمعصمك. اقترب وقتك. | العمل، ضمن صورة حياتك. ✎ |

ASC: en-GB reuses en and es-MX reuses es, as in 3.2.1; the other 16 store
locales get their own video (zh-Hans ← zh-CN, zh-Hant ← zh-TW).

## Spec

1920×1280, 24 s, 30 fps (720 frames), H.264 yuv420p BT.709, no audio, loops.
Every frame is audited in the renderer: headline glyphs and hero inside the
safe area, no clipped text, settled copy clear of every visible surface,
headline ≥ 56 px. A violation stops the render.

The countdown, widget, focus, report and Watch clips are recorded live and
wrap across the loop point, so the digits keep counting from 23.9 s into 0 s.

## Reproduce

```sh
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /private/tmp/owc-322-creative-build CODE_SIGNING_ALLOWED=NO build
IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/creative-capture-search-3.2.2.mjs
IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/creative-search-3.2.2.mjs
```

Raw captures land in `scripts/marketing-shots/ios/raw/3.2.2/search/`, videos
and the manifest in `scripts/marketing-shots/ios/out/creative-3.2.2/search/`
(both ignored). Review frames and the manifest copy are in this folder.

Capture notes:
- `ReleaseNotes.current` is still 3.2.1, so `releaseNotesSeen` stays 3.2.1;
  anything else puts the What's New sheet over the timer, focus and records.
- Onboarding chooses its holiday template from the locale region. On a US
  public holiday (Columbus Day, the capture day) the en widget preview read
  "Next shift in". The en widget scene uses `en_001` so it counts down the
  live shift; every other scene keeps `en_US`.
- Records and leave screens are static once settled, so their animation is
  composed from native pixels: `creative-marks.py` finds the calendar cells
  that carry marks in the capture, and masks over them are removed in reading
  order. Row bands are in `SCENES`.
- Records are seeded relative to the capture week (the two weeks before it),
  so the visible dates follow the capture day; capture every language on the
  same day (all 18 were captured on 2026-10-12, Asia/Shanghai). The seed
  follows each locale's working week, so Arabic (Sunday–Thursday) gets the
  same pattern on its own workdays.
- Thai, Devanagari, Arabic and Vietnamese set calendar rows lower than
  English. The renderer finds each capture's run highlight / record bars
  (`creative-marks.py` anchor mode) and shifts that crop and its reveal masks
  by the difference (`rowShift` in the manifest). The widget preview's
  height also varies with the onboarding title's length, so its crop follows
  `creative-widget-crop.py`. Arabic reveals right to left and its headline
  and heroes anchor to the right.
- The cycle report opens at a different moment in each recording. The
  renderer finds the end of its opening chapter (`creative-marks.py
  reportHours`) and starts the clip 0.6 s into the hours chapter (`inPoint`
  in the manifest); reports are recorded for 26 s so at least four seconds of
  hours remain whatever the delay.

## Status (2026-10-13)

All 18 locales rendered locally and reviewed (`search-review/<locale>-safe-area-sheet.jpg`,
eight beats each with the safe area outlined); nothing uploaded, bound or
submitted. Every video is 1920×1280, 30 fps, 720 frames, yuv420p, no audio,
and every frame passed the safe-area, clipping and overlap audit. No locale
falls below its headline floor.

Captured on 2026-10-12 (Asia/Shanghai) for every locale; the de, fr, ja and
id cycle-report recordings were redone after midnight because the report had
opened too late, and show the same September 2026 report.

| Locale | ASC | Headline px | Report in-point | Row shift (records, leave) | Widget shift | Frames audited | SHA-256 |
|---|---|---|---|---|---|---|---|
| ar | ar-SA | 88 | 5.9 s | 17, 36 | 6 | 733 | `e85986b4d335` |
| de | de-DE | 64 | 6.5 s | 0, 0 | 51 | 733 | `3be89435c112` |
| en | en-US + en-GB | 78 | 5.6 s | 0, 0 | 0 | 733 | `013416a5ae11` |
| es | es-ES + es-MX | 66 | 6.3 s | 0, 0 | -156 | 733 | `c69b4fbe0384` |
| fr | fr-FR | 68 | 8.9 s | 0, 0 | -74 | 733 | `f02689a8d2a6` |
| hi-IN | hi | 72 | 5.8 s | 22, 60 | 14 | 733 | `7c440e1304d9` |
| id | id | 67 | 11.1 s | 0, 0 | 0 | 733 | `ece5dd928f25` |
| it | it | 69 | 6.2 s | 0, 0 | -74 | 733 | `e135e49fdac3` |
| ja | ja | 68 | 9.5 s | 0, 0 | -113 | 733 | `93d001e793af` |
| ko | ko | 73 | 6.6 s | 0, 0 | 32 | 733 | `193602e43a01` |
| mr-IN | mr-IN | 79 | 11.4 s | 22, 60 | 14 | 733 | `d2d964b79476` |
| pt | pt-BR | 70 | 5.8 s | 0, 0 | -74 | 733 | `a6b1a324a833` |
| ru | ru | 65 | 5.6 s | 0, 0 | -156 | 733 | `84e013890c2a` |
| th | th | 77 | 6.2 s | 22, 60 | 51 | 733 | `cdfcb5b02e82` |
| tr | tr | 65 | 5.6 s | 0, 0 | 0 | 733 | `1bd2b5f87779` |
| vi | vi | 75 | 6 s | 17, 36 | -89 | 733 | `937dcc174318` |
| zh-CN | zh-Hans | 93 | 5.6 s | 0, 0 | 0 | 733 | `f28615ce33eb` |
| zh-TW | zh-Hant | 85 | 10.1 s | 0, 0 | 0 | 733 | `a64f1f12ccf8` |

Review fixes applied before hand-off: the widget preview crop now follows
each locale's preview position; the report in-point follows each recording;
en, es and pt widgets use a region-less locale because 12 October is a
public holiday in the US, Spain and Brazil.
