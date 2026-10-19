# iOS 3.2.3 · Widget screenshot pages (local, not uploaded)

Two new pages for the iPhone 6.9″ set (`APP_IPHONE_67`, 1320×2868, opaque
PNG), in the approved 3.2.1/3.2.2 page layout, rendered by
`scripts/marketing-shots/ios/creative-compose-shots-3.2.3.mjs`.

| Page | Shows | zh-CN | en |
|---|---|---|---|
| 3 · Home Screen | Real Home Screen of free widgets: classic countdown, ring, week progress, 7-day shifts | 全新小组件 · 不用打开，桌面就有数。 · 倒计时、本周进度、班表与节假日，多款小组件免费可用。 | NEW WIDGETS · Your day, on your Home Screen. · Countdown, week progress, shifts and holidays. Many of them free. |
| 4 · Lock Screen & Watch | Real Lock Screen (countdown, ring, week, weekend line, Start shift and clock-off controls) with the Watch countdown in front | 锁屏 · Apple Watch · 锁屏一亮，就知道还剩多久。 · 锁屏小组件、一键开始上班，Apple Watch 也能看。 | LOCK SCREEN · APPLE WATCH · Wake your screen. See how long is left. · Lock Screen widgets, a Start shift control and your countdown on Apple Watch. |

Changes from the approved plan: the page 4 label drops “Control Center” and
the en subline says “your countdown on Apple Watch” rather than
“complications”, because the page shows Lock Screen controls and the Watch
app. The Watch fixture's status-bar clock (capture time, not the phone's) is
blacked out; the rest of the Watch screen is native.

## New order (10 per set)

1–2 countdown opener, **3 Home Screen widgets**, **4 Lock Screen & Watch**,
5 time off, 6 cycle report, 7 calendar, 8 records, 9 focus, 10 rest. The old
Watch page (5) and widgets page (9) retire; pages 1–2 and 5–10 keep their
3.2.2 uploads. iPad and Duo sets are unchanged.

## All locales

The 17 store locales have both pages (mr-IN has no store screenshot set).
zh-CN and en were reviewed; the other headlines are written for 3.2.3 and
need review. Each page shows the locale's own Home Screen and Lock Screen,
captured in that system language. Arabic is right to left, with the phone
and Watch mirrored on page 4.

| Locale | Page 3 (Home Screen) | Page 4 (Lock Screen & Watch) |
|---|---|---|
| zh-CN | 不用打开， 桌面就有数。 | 锁屏一亮， 就知道还剩多久。 |
| en | Your day, on your Home Screen. | Wake your screen. See how long is left. |
| zh-TW | 不打開， 主畫面就看得到。 | 螢幕一亮， 就知道還剩多久。 |
| ja | 開かなくても、 ホーム画面でわかる。 | 画面をつければ、 あと何分かわかる。 |
| ko | 열지 않아도, 홈 화면에서 한눈에. | 화면을 켜면, 남은 시간이 보여요. |
| de | Dein Tag, auf dem Home-Bildschirm. | Bildschirm an. Restzeit im Blick. |
| fr | Votre journée, sur l’écran d’accueil. | Un regard. Le temps restant. |
| es | Tu día, en la pantalla de inicio. | Enciende la pantalla. Mira cuánto falta. |
| it | La tua giornata, sulla schermata Home. | Accendi lo schermo. Vedi quanto manca. |
| pt | Seu dia, na Tela de Início. | Acenda a tela. Veja quanto falta. |
| ru | Ваш день — на экране «Домой». | Взгляд на экран — сколько осталось. |
| tr | Günün, ana ekranında. | Ekranı aç, kalan süreyi gör. |
| id | Harimu, di Layar Utama. | Nyalakan layar, lihat sisa waktu. |
| vi | Ngày của bạn, ngay trên màn hình chính. | Bật màn hình, biết còn bao lâu. |
| th | วันทำงานของคุณ บนหน้าจอโฮม | เปิดหน้าจอ ก็รู้ว่าเหลืออีกนาน |
| hi-IN | आपका दिन, होम स्क्रीन पर। | स्क्रीन जगाइए, बचा समय देखिए। |
| ar | يومك، على الشاشة الرئيسية. | أضئ الشاشة، واعرف كم تبقّى. |

Known difference: the Watch on page 4 is the Watch app's review fixture,
fixed at 2:37:5x left, so it does not match the phone's countdown.

## Status (2026-10-19)

34 pages rendered and audited (`creative-audit-3.2.3.mjs`: 1320×2868, opaque
RGB, layout audit, source hashes, poster fonts only; no findings). Review
sheets: `shots-review/page3-all-locales.jpg`, `page4-all-locales.jpg`;
manifest: `screenshot-manifest.json`. Nothing uploaded.

The other pages of each set keep their 3.2.2 uploads, except those
re-rendered for the font fix (`font-fallback-fix.md`, `pages-manifest.json`,
`pages-review/`).
