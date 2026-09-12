// 微软商店商品页的 19 个语言文案，供 listing-import.mjs 生成导入用的 CSV。
//
// 每个语言对应一个应用界面语言（appLanguage），截图就按那个前缀从 windows/out/ 取。
// `isNewLanguage` 的是 3.1.9 这一轮新开的商品页语言：它们在导出的 CSV 里还没有列，
// 所以除了描述和更新说明，还要补简介、功能条目和搜索词；原有六个语言的这些字段
// 已经在商店里，本轮只改描述、更新说明、统计那条功能和截图。
//
// 术语跟随应用内译文（木鱼 / 목탁 / mõ gỗ / Woodfish），称呼跟随该语言商品页
// 描述已有的口吻（德语用 Sie，印尼语用 Anda）。
//
// ⚠️ 印尼语用 id-id，不能用同样合法的 id：CSV 第二列就叫 ID，加一列叫 id 的语言列
// 会让导入在处理到它时失败——报错依旧没有任何内容。走 API 时会换回 id。
//
// ⚠️ searchTerms 的限制是**所有词条加起来不超过 21 个词**，不是每条 21 个词。
// 超了 API 会明确报 KeywordsTotalCount；网页端导入则又是一句没有内容的错误。改文案前先读 add-and-edit-store-
// listing-info 的字段上限：描述 10000、更新说明 1500、功能每条 200、简介建议 270 内。

export const SHOTS = ["countdown", "mini-woodfish", "stats", "setup", "settings"];

export const LISTINGS = {
  "en-us": {
    "appLanguage": "en",
    "description": "See exactly how much of your workday is left.\n\nDoneAt turns your shift into one calm number: the time remaining, how far through the day you are, and — if you want it — what you have earned so far, ticking up second by second.\n\nSet your hours once. The countdown lives in your system tray, so a glance at the corner of the screen is enough. A global shortcut brings the window back without hunting through browser tabs, and a small floating timer can sit on top of your work if you want the number always in view.\n\nIt fits real schedules: nine to five, a twelve-hour day, or a night shift that runs past midnight. Lunch breaks pause the count. Overtime extends it. Gentle reminders let you know when you are halfway, nearly there, and free to go, and optional health reminders nudge you to drink water or stand up.\n\nNew in this version: an Activity page that keeps a monthly log — days worked, hours including overtime, and how many times you knocked the woodfish on the mini timer. That log stays on this PC like everything else.\n\nYour hours, your salary and your preferences stay on your device. There is no account to create, nothing is uploaded, and the app collects no analytics. The countdown and the earnings estimate are calculated locally.\n\nFree and open source under the MIT licence. The full source is on GitHub, so every claim on this page can be checked against the code.\n\nThe app interface is available in 19 languages: English, Simplified Chinese, Traditional Chinese (Taiwan and Hong Kong), Japanese, Korean, French, German, Spanish, Italian, Portuguese, Russian, Hindi, Marathi, Turkish, Arabic, Thai, Indonesian and Vietnamese.",
    "releaseNotes": "What's new in 3.1.9:\n\n• Activity page in Settings: see each month's days worked, hours including overtime, and woodfish knocks. Everything stays on this PC.\n• The woodfish now keeps counting past 999, and every day's knocks are saved.\n• Accessibility text scaling in Windows no longer enlarges the whole window.\n• Smoother page transitions and small fixes.",
    "feature15": "Monthly activity log: days worked, hours and woodfish knocks",
    "captions": [
      "Countdown",
      "Mini timer",
      "Activity",
      "Work hours",
      "Settings"
    ]
  },
  "zh": {
    "appLanguage": "zh-CN",
    "description": "一眼看清今天还剩多少工作时间。\n\nDoneAt 将你的班次化作一个安静清晰的数字：剩余时间、今天已过的进度，以及——如果你愿意——截至此刻的收入，按秒实时增长。\n\n只需设置一次工作时间。倒计时常驻系统托盘，瞥一眼屏幕角落就够了。通过全局快捷键，无需在浏览器标签页里翻找即可重新打开窗口；如果你希望数字始终可见，也可以让一个小型悬浮计时器置于工作内容之上。\n\n它适配真实的排班：朝九晚五、十二小时工作日，或跨越午夜的夜班。午休会暂停倒计时，加班会延长倒计时。温和的提醒会在过半、快结束以及可以下班时告诉你；可选的健康提醒则会提示你喝水或起身活动。\n\n本次新增“统计”页：按月记录出勤天数、含加班的工时，以及在迷你计时器上敲木鱼的次数。这些记录和其他数据一样，只保存在这台电脑上。\n\n你的工时、薪资与偏好均保留在设备上。无需创建账户，不会上传任何内容，应用也不会收集分析数据。倒计时和收入估算均在本地计算。\n\n基于 MIT 许可证免费开源。完整源代码托管在 GitHub，因此本页面中的每一项说明都可以对照代码核实。\n\n应用界面提供 19 种语言：英语、简体中文、繁体中文（台湾和香港）、日语、韩语、法语、德语、西班牙语、意大利语、葡萄牙语、俄语、印地语、马拉地语、土耳其语、阿拉伯语、泰语、印尼语和越南语。",
    "releaseNotes": "3.1.9 更新内容：\n\n• 设置里新增“统计”页：按月查看出勤天数、含加班的工时和敲木鱼的次数，数据只保存在这台电脑上。\n• 木鱼计数不再停在 999，每天敲了多少下都会记下来。\n• Windows 的文本放大设置不再把整个窗口一起放大。\n• 页面切换更顺滑，并修复了一些小问题。",
    "feature15": "统计页：按月记录出勤天数、工时和木鱼次数",
    "captions": [
      "倒计时",
      "迷你计时器",
      "统计",
      "上下班时间",
      "设置"
    ]
  },
  "ko-kr": {
    "appLanguage": "ko",
    "description": "오늘 근무 시간이 얼마나 남았는지 한눈에 확인하세요.\n\nDoneAt은 근무를 하나의 차분한 숫자로 보여 줍니다. 남은 시간, 하루가 얼마나 진행되었는지, 그리고 원한다면 지금까지 번 금액까지 초 단위로 계속 표시합니다.\n\n근무 시간을 한 번만 설정하세요. 카운트다운은 시스템 트레이에 머무르므로 화면 구석을 보기만 하면 됩니다. 전역 단축키로 브라우저 탭을 뒤질 필요 없이 창을 다시 열 수 있고, 숫자를 늘 보려면 작은 플로팅 타이머를 작업 위에 띄울 수 있습니다.\n\n현실적인 근무 일정에 맞춥니다. 9시부터 5시까지, 12시간 근무, 자정을 넘기는 야간 근무까지 가능합니다. 점심시간에는 카운트가 멈추고, 초과 근무에는 시간이 연장됩니다. 절반, 거의 끝, 퇴근할 때를 부드럽게 알려 주며, 선택한 건강 알림은 물을 마시거나 일어나 스트레칭하도록 알려 줍니다.\n\n이번 버전에서는 통계 페이지가 추가되었습니다. 월별 출근 일수, 초과 근무를 포함한 근무 시간, 미니 타이머에서 목탁을 두드린 횟수를 기록합니다. 이 기록도 다른 데이터와 마찬가지로 이 PC에만 저장됩니다.\n\n근무 시간, 급여 및 환경설정은 기기에만 저장됩니다. 계정을 만들 필요가 없고, 아무것도 업로드하지 않으며, 앱은 분석 데이터를 수집하지 않습니다. 카운트다운과 수입 추정은 로컬에서 계산됩니다.\n\nMIT 라이선스로 무료 공개 소스입니다. 전체 소스는 GitHub에 있어 이 페이지의 모든 설명을 코드와 대조해 확인할 수 있습니다.\n\n앱 인터페이스는 영어, 중국어 간체, 중국어 번체(대만 및 홍콩), 일본어, 한국어, 프랑스어, 독일어, 스페인어, 이탈리아어, 포르투갈어, 러시아어, 힌디어, 마라티어, 터키어, 아랍어, 태국어, 인도네시아어, 베트남어 등 19개 언어로 제공됩니다.",
    "releaseNotes": "3.1.9의 새로운 기능:\n\n• 설정에 통계 페이지가 추가되었습니다. 월별 출근 일수, 초과 근무를 포함한 근무 시간, 목탁을 두드린 횟수를 확인할 수 있으며 모든 기록은 이 PC에만 저장됩니다.\n• 목탁 횟수가 999에서 멈추지 않고, 하루하루의 기록이 남습니다.\n• Windows의 텍스트 크기 설정이 창 전체를 확대하던 문제를 해결했습니다.\n• 페이지 전환이 더 부드러워지고 작은 문제들을 고쳤습니다.",
    "feature15": "월별 통계: 출근 일수, 근무 시간, 목탁 횟수",
    "captions": [
      "카운트다운",
      "미니 타이머",
      "통계",
      "근무 시간",
      "설정"
    ]
  },
  "de": {
    "appLanguage": "de",
    "description": "Sehen Sie auf einen Blick, wie viel von Ihrem Arbeitstag noch übrig ist.\n\nDoneAt verdichtet Ihre Schicht zu einer ruhigen Zahl: die verbleibende Zeit, den Fortschritt des Tages und – wenn Sie möchten – Ihren bisherigen Verdienst, der sekundenweise weiterläuft.\n\nLegen Sie Ihre Arbeitszeit einmal fest. Der Countdown bleibt im Infobereich der Taskleiste; ein Blick in die Bildschirmecke genügt. Mit einem globalen Tastenkürzel holen Sie das Fenster zurück, ohne Browser-Tabs durchsuchen zu müssen. Wenn die Zahl immer sichtbar sein soll, kann ein kleiner schwebender Timer über Ihrer Arbeit liegen.\n\nEr passt zu echten Arbeitsplänen: von neun bis fünf, einem Zwölf-Stunden-Tag oder einer Nachtschicht über Mitternacht hinaus. Mittagspausen halten den Zähler an. Überstunden verlängern ihn. Dezente Erinnerungen melden sich zur Halbzeit, kurz vor Schluss und zum Feierabend; optionale Gesundheits-Erinnerungen regen dazu an, Wasser zu trinken oder aufzustehen.\n\nNeu in dieser Version: eine Seite „Aktivität“ mit einem Monatsprotokoll – Arbeitstage, Stunden inklusive Überstunden und wie oft Sie den Woodfish im Mini-Timer angeschlagen haben. Das Protokoll bleibt wie alles andere auf diesem PC.\n\nIhre Arbeitszeiten, Ihr Gehalt und Ihre Einstellungen bleiben auf Ihrem Gerät. Sie müssen kein Konto anlegen, nichts wird hochgeladen, und die App sammelt keine Analysedaten. Countdown und Verdienstschätzung werden lokal berechnet.\n\nKostenlos und quelloffen unter der MIT-Lizenz. Der vollständige Quellcode liegt auf GitHub; jede Aussage auf dieser Seite lässt sich daher im Code überprüfen.\n\nDie App-Oberfläche ist in 19 Sprachen verfügbar: Englisch, Vereinfachtes Chinesisch, Traditionelles Chinesisch (Taiwan und Hongkong), Japanisch, Koreanisch, Französisch, Deutsch, Spanisch, Italienisch, Portugiesisch, Russisch, Hindi, Marathi, Türkisch, Arabisch, Thailändisch, Indonesisch und Vietnamesisch.",
    "releaseNotes": "Neu in 3.1.9:\n\n• Seite „Aktivität“ in den Einstellungen: Arbeitstage, Stunden inklusive Überstunden und Woodfish-Schläge für jeden Monat. Alles bleibt auf diesem PC.\n• Der Woodfish zählt jetzt über 999 hinaus, und die Schläge jedes Tages werden gespeichert.\n• Die Windows-Einstellung für größere Textanzeige vergrößert nicht mehr das gesamte Fenster.\n• Flüssigere Seitenwechsel und kleine Korrekturen.",
    "feature15": "Monatsprotokoll: Arbeitstage, Stunden und Woodfish-Schläge",
    "captions": [
      "Countdown",
      "Mini-Timer",
      "Aktivität",
      "Arbeitszeiten",
      "Einstellungen"
    ]
  },
  "ja": {
    "appLanguage": "ja",
    "description": "今日の勤務時間があとどれくらい残っているかを、ひと目で確認できます。\n\nDoneAt は、勤務をひとつの落ち着いた数字で示します。残り時間、勤務日の進み具合、そして必要なら、これまでの収入を秒ごとに表示します。\n\n勤務時間は一度設定するだけです。カウントダウンはシステム トレイに常駐するため、画面の隅を見るだけで確認できます。グローバル ショートカットでブラウザーのタブを探し回ることなくウィンドウを戻せます。また、数字を常に見ていたい場合は、小さなフローティング タイマーを作業の上に表示できます。\n\n実際の勤務スケジュールに対応します。9 時から 17 時までの勤務、12 時間勤務、日付をまたぐ夜勤にも使えます。昼休みにはカウントが一時停止し、残業では延長されます。半分経過時、終業間近、退勤時には控えめに知らせ、任意の健康リマインダーが水分補給や立ち上がることを促します。\n\n今回のアップデートで「記録」ページを追加しました。月ごとの出勤日数、残業を含む勤務時間、ミニタイマーで木魚を叩いた回数を記録します。記録も他のデータと同じく、このPCの中だけに保存されます。\n\n勤務時間、給与、設定はすべてデバイス上に保存されます。アカウントの作成は不要で、何もアップロードされず、アプリが分析データを収集することもありません。カウントダウンと収入の見積もりはローカルで計算されます。\n\nMIT ライセンスのもとで無料のオープンソースです。完全なソースコードは GitHub で公開されているため、このページの記載はすべてコードで確認できます。\n\nアプリのインターフェースは、英語、簡体字中国語、繁体字中国語（台湾・香港）、日本語、韓国語、フランス語、ドイツ語、スペイン語、イタリア語、ポルトガル語、ロシア語、ヒンディー語、マラーティー語、トルコ語、アラビア語、タイ語、インドネシア語、ベトナム語を含む19言語で利用できます。",
    "releaseNotes": "3.1.9 の新機能：\n\n• 設定に「記録」ページを追加。月ごとの出勤日数、残業を含む勤務時間、木魚を叩いた回数を確認できます。データはこのPCの中だけに保存されます。\n• 木魚のカウントが999で止まらなくなり、毎日の回数が記録されます。\n• Windows の文字サイズの設定でウィンドウ全体が拡大されてしまう問題を修正しました。\n• ページの切り替えをなめらかにし、細かな不具合を修正しました。",
    "feature15": "月ごとの記録：出勤日数、勤務時間、木魚の回数",
    "captions": [
      "カウントダウン",
      "ミニタイマー",
      "記録",
      "勤務時間",
      "設定"
    ]
  },
  "zh-hant": {
    "appLanguage": "zh-TW",
    "description": "一眼看清今天還剩多少工作時間。\n\nDoneAt 將你的班次化作一個安靜清晰的數字：剩餘時間、今天已過的進度，以及——如果你願意——截至此刻的收入，按秒即時增加。\n\n只需設定一次工作時間。倒數計時會常駐在系統匣，瞥一眼螢幕角落就夠了。透過全域快速鍵，無需在瀏覽器分頁中翻找即可重新開啟視窗；如果你希望數字始終可見，也可以讓小型懸浮計時器置於工作內容之上。\n\n它適配真實的排班：朝九晚五、十二小時工作日，或跨越午夜的夜班。午休會暫停倒數計時，加班會延長倒數計時。溫和的提醒會在過半、快結束以及可以下班時告訴你；可選的健康提醒則會提示你喝水或起身活動。\n\n本次新增「統計」頁：按月記錄出勤天數、含加班的工時，以及在迷你計時器上敲木魚的次數。這些記錄和其他資料一樣，只儲存在這台電腦上。\n\n你的工時、薪資與偏好均保留在裝置上。無需建立帳戶，不會上傳任何內容，應用程式也不會收集分析資料。倒數計時和收入估算均在本機計算。\n\n基於 MIT 授權條款免費開源。完整原始碼託管在 GitHub，因此本頁中的每一項說明都可以對照程式碼核實。\n\n應用程式介面提供 19 種語言：英語、簡體中文、繁體中文（台灣和香港）、日語、韓語、法語、德語、西班牙語、義大利語、葡萄牙語、俄語、印地語、馬拉地語、土耳其語、阿拉伯語、泰語、印尼語和越南語。",
    "releaseNotes": "3.1.9 更新內容：\n\n• 設定裡新增「統計」頁：按月查看出勤天數、含加班的工時和敲木魚的次數，資料只儲存在這台電腦上。\n• 木魚計數不再停在 999，每天敲了幾下都會記下來。\n• Windows 的文字放大設定不再把整個視窗一起放大。\n• 頁面切換更順暢，並修正了一些小問題。",
    "feature15": "統計頁：按月記錄出勤天數、工時和木魚次數",
    "captions": [
      "倒數計時",
      "迷你計時器",
      "統計",
      "上下班時間",
      "設定"
    ]
  },
  "fr": {
    "appLanguage": "fr",
    "isNewLanguage": true,
    "shortDescription": "Voyez combien de temps il reste dans votre journée. Un compte à rebours discret dans la zone de notification, avec le total facultatif de vos gains du jour. Tous les horaires, nuits comprises. Tout reste sur votre appareil : pas de compte, aucun envoi.",
    "description": "Voyez exactement combien de temps il reste dans votre journée de travail.\n\nDoneAt réduit votre journée à un chiffre calme : le temps restant, votre progression et — si vous le souhaitez — ce que vous avez gagné jusqu’ici, qui augmente seconde après seconde.\n\nRéglez vos horaires une fois. Le compte à rebours vit dans la zone de notification : un coup d’œil dans le coin de l’écran suffit. Un raccourci global ramène la fenêtre sans fouiller dans les onglets du navigateur, et un petit minuteur flottant peut rester au-dessus de votre travail si vous voulez le chiffre toujours visible.\n\nIl s’adapte aux vrais plannings : de neuf à cinq, une journée de douze heures ou un poste de nuit qui passe minuit. La pause déjeuner met le compte en pause. Les heures supplémentaires le prolongent. Des rappels discrets vous signalent la mi-journée, la dernière ligne droite et l’heure de partir ; des rappels santé facultatifs vous invitent à boire de l’eau ou à vous lever.\n\nNouveau dans cette version : une page Activité qui tient un journal mensuel — jours travaillés, heures supplémentaires comprises, et combien de fois vous avez frappé le Woodfish sur le minuteur flottant. Ce journal reste sur ce PC, comme le reste.\n\nVos horaires, votre salaire et vos préférences restent sur votre appareil. Aucun compte à créer, rien n’est envoyé, et l’application ne collecte aucune donnée d’analyse. Le compte à rebours et l’estimation des gains sont calculés localement.\n\nGratuit et open source sous licence MIT. Le code source complet est sur GitHub : chaque affirmation de cette page peut être vérifiée dans le code.\n\nL’interface de l’application est disponible en 19 langues, dont le français.",
    "releaseNotes": "Nouveautés de la version 3.1.9 :\n\n• Page Activité dans les réglages : jours travaillés, heures supplémentaires comprises et frappes du Woodfish, mois par mois. Tout reste sur ce PC.\n• Le Woodfish compte désormais au-delà de 999 et garde les frappes de chaque jour.\n• L’agrandissement du texte de Windows n’agrandit plus toute la fenêtre.\n• Transitions plus fluides entre les pages et petites corrections.",
    "features": [
      "Compte à rebours en direct dans la zone de notification",
      "Total facultatif des gains du jour",
      "Tous les horaires, y compris les nuits après minuit",
      "La pause déjeuner met le compte en pause",
      "Les heures supplémentaires prolongent le compte",
      "Rappels à 50 %, 75 %, 90 % et 95 %",
      "Rappels facultatifs d’hydratation et d’étirement",
      "Minuteur flottant, toujours au premier plan",
      "Raccourci global pour afficher ou masquer la fenêtre",
      "Lancement au démarrage de Windows",
      "Fonctionne hors ligne, sans compte",
      "Rien n’est envoyé, aucune analyse",
      "Gratuit et open source (MIT)",
      "Interface en 19 langues"
    ],
    "feature15": "Journal mensuel : jours travaillés, heures et frappes du Woodfish",
    "searchTerms": [
      "compte à rebours travail",
      "minuteur journée travail",
      "fin de journée",
      "heures de travail",
      "minuteur barre des tâches",
      "suivi salaire"
    ],
    "captions": [
      "Compte à rebours",
      "Minuteur flottant",
      "Activité",
      "Horaires",
      "Réglages"
    ]
  },
  "es": {
    "appLanguage": "es",
    "isNewLanguage": true,
    "shortDescription": "Mira exactamente cuánto queda de tu jornada. Una cuenta atrás discreta en el área de notificación, con un total opcional de lo que has ganado hoy. Funciona con cualquier turno, incluidos los nocturnos. Todo se queda en tu equipo: sin cuenta y sin subidas.",
    "description": "Mira exactamente cuánto queda de tu jornada de trabajo.\n\nDoneAt convierte tu turno en una cifra tranquila: el tiempo que queda, cuánto llevas del día y —si lo quieres— lo que has ganado hasta ahora, sumando segundo a segundo.\n\nConfigura tu horario una vez. La cuenta atrás vive en el área de notificación, así que basta con mirar la esquina de la pantalla. Un atajo global devuelve la ventana sin rebuscar entre pestañas, y un pequeño temporizador flotante puede quedarse sobre tu trabajo si quieres tener la cifra siempre a la vista.\n\nSe adapta a horarios reales: de nueve a cinco, jornadas de doce horas o un turno de noche que pasa de medianoche. La pausa de la comida detiene la cuenta. Las horas extra la alargan. Avisos discretos te indican cuándo vas por la mitad, cuándo queda poco y cuándo puedes irte; los recordatorios de salud opcionales te invitan a beber agua o a levantarte.\n\nNuevo en esta versión: una página Actividad que guarda un registro mensual: días trabajados, horas con horas extra y cuántas veces has golpeado el Woodfish en el temporizador flotante. Ese registro se queda en este PC, como todo lo demás.\n\nTu horario, tu salario y tus preferencias se quedan en tu equipo. No hay que crear ninguna cuenta, no se sube nada y la aplicación no recopila datos de análisis. La cuenta atrás y la estimación de ingresos se calculan localmente.\n\nGratis y de código abierto con licencia MIT. El código completo está en GitHub, así que cada afirmación de esta página puede comprobarse en el código.\n\nLa interfaz de la aplicación está disponible en 19 idiomas, incluido el español.",
    "releaseNotes": "Novedades de la versión 3.1.9:\n\n• Página Actividad en los ajustes: días trabajados, horas con horas extra y toques del Woodfish, mes a mes. Todo se queda en este PC.\n• El Woodfish ya cuenta más allá de 999 y guarda los toques de cada día.\n• El tamaño de texto de Windows ya no agranda toda la ventana.\n• Transiciones más fluidas entre páginas y pequeñas correcciones.",
    "features": [
      "Cuenta atrás en directo en el área de notificación",
      "Total opcional de lo ganado hoy",
      "Cualquier turno, incluidas noches que pasan de medianoche",
      "La pausa de la comida detiene la cuenta",
      "Las horas extra alargan la cuenta atrás",
      "Avisos al 50 %, 75 %, 90 % y 95 %",
      "Recordatorios opcionales para beber agua y estirarse",
      "Temporizador flotante, siempre visible",
      "Atajo global para mostrar u ocultar la ventana",
      "Inicio con Windows",
      "Funciona sin conexión y sin cuenta",
      "No se sube nada, sin analíticas",
      "Gratis y de código abierto (MIT)",
      "Interfaz en 19 idiomas"
    ],
    "feature15": "Registro mensual: días trabajados, horas y toques del Woodfish",
    "searchTerms": [
      "cuenta atrás trabajo",
      "temporizador jornada laboral",
      "fin de jornada",
      "horas de trabajo",
      "temporizador bandeja sistema",
      "seguimiento salario",
      "contador turno"
    ],
    "captions": [
      "Cuenta atrás",
      "Temporizador flotante",
      "Actividad",
      "Horario",
      "Ajustes"
    ]
  },
  "it": {
    "appLanguage": "it",
    "isNewLanguage": true,
    "shortDescription": "Guarda quanto manca alla fine della giornata. Un conto alla rovescia discreto nell’area di notifica, con il totale facoltativo dei guadagni di oggi. Qualsiasi turno, notti comprese. Tutto resta sul tuo PC: nessun account, nessun caricamento.",
    "description": "Guarda esattamente quanto manca alla fine della tua giornata di lavoro.\n\nDoneAt riduce il tuo turno a un numero tranquillo: il tempo che manca, a che punto sei della giornata e — se vuoi — quanto hai guadagnato finora, che sale secondo dopo secondo.\n\nImposta l’orario una volta sola. Il conto alla rovescia vive nell’area di notifica: basta un’occhiata all’angolo dello schermo. Una scorciatoia globale riporta la finestra senza cercare tra le schede del browser, e un piccolo timer fluttuante può restare sopra il tuo lavoro se vuoi il numero sempre in vista.\n\nSi adatta agli orari reali: dalle nove alle cinque, giornate di dodici ore o un turno di notte che supera la mezzanotte. La pausa pranzo mette in pausa il conto. Gli straordinari lo prolungano. Promemoria discreti ti avvisano a metà, quasi alla fine e quando puoi andare; i promemoria per la salute, facoltativi, ti ricordano di bere o di alzarti.\n\nNovità di questa versione: una pagina Attività che tiene un registro mensile — giorni lavorati, ore con gli straordinari e quante volte hai battuto il Woodfish sul timer fluttuante. Il registro resta su questo PC, come tutto il resto.\n\nIl tuo orario, il tuo stipendio e le tue preferenze restano sul tuo dispositivo. Non serve creare un account, non viene caricato nulla e l’app non raccoglie dati analitici. Il conto alla rovescia e la stima dei guadagni sono calcolati in locale.\n\nGratuita e open source con licenza MIT. Il codice completo è su GitHub, quindi ogni affermazione di questa pagina può essere verificata nel codice.\n\nL’interfaccia dell’app è disponibile in 19 lingue, italiano incluso.",
    "releaseNotes": "Novità della versione 3.1.9:\n\n• Pagina Attività nelle impostazioni: giorni lavorati, ore con gli straordinari e colpi di Woodfish, mese per mese. Tutto resta su questo PC.\n• Il Woodfish ora conta oltre 999 e salva i colpi di ogni giorno.\n• L’ingrandimento del testo di Windows non ingrandisce più l’intera finestra.\n• Passaggi tra le pagine più fluidi e piccole correzioni.",
    "features": [
      "Conto alla rovescia in tempo reale nell’area di notifica",
      "Totale facoltativo dei guadagni di oggi",
      "Qualsiasi turno, comprese le notti oltre la mezzanotte",
      "La pausa pranzo mette in pausa il conto",
      "Gli straordinari prolungano il conto alla rovescia",
      "Promemoria al 50%, 75%, 90% e 95%",
      "Promemoria facoltativi per bere e sgranchirsi",
      "Timer fluttuante, sempre in primo piano",
      "Scorciatoia globale per mostrare o nascondere la finestra",
      "Avvio con Windows",
      "Funziona offline, senza account",
      "Nessun caricamento, nessuna analisi",
      "Gratuito e open source (MIT)",
      "Interfaccia in 19 lingue"
    ],
    "feature15": "Registro mensile: giorni lavorati, ore e colpi di Woodfish",
    "searchTerms": [
      "conto alla rovescia lavoro",
      "timer giornata lavorativa",
      "fine turno",
      "ore di lavoro",
      "timer barra applicazioni",
      "monitoraggio stipendio",
      "timer turno"
    ],
    "captions": [
      "Conto alla rovescia",
      "Timer fluttuante",
      "Attività",
      "Orario",
      "Impostazioni"
    ]
  },
  "pt": {
    "appLanguage": "pt",
    "isNewLanguage": true,
    "shortDescription": "Veja exatamente quanto falta do seu dia de trabalho. Uma contagem decrescente discreta na área de notificação, com um total opcional do que ganhou hoje. Funciona com qualquer turno, incluindo noites. Fica tudo no seu PC: sem conta e sem envios.",
    "description": "Veja exatamente quanto falta do seu dia de trabalho.\n\nO DoneAt reduz o seu turno a um número calmo: o tempo que falta, quanto já passou do dia e — se quiser — quanto ganhou até agora, a subir segundo a segundo.\n\nDefina o seu horário uma vez. A contagem decrescente fica na área de notificação, por isso basta olhar para o canto do ecrã. Um atalho global traz a janela de volta sem procurar entre separadores, e um pequeno temporizador flutuante pode ficar por cima do seu trabalho se quiser o número sempre à vista.\n\nAdapta-se a horários reais: das nove às cinco, jornadas de doze horas ou um turno da noite que passa da meia-noite. A pausa para almoço suspende a contagem. As horas extra prolongam-na. Lembretes discretos avisam-no a meio, quase no fim e quando pode sair; os lembretes de saúde, opcionais, sugerem beber água ou levantar-se.\n\nNovidade nesta versão: uma página Atividade que mantém um registo mensal — dias trabalhados, horas com horas extra e quantas vezes bateu no Woodfish no temporizador flutuante. Esse registo fica neste PC, tal como tudo o resto.\n\nO seu horário, o seu salário e as suas preferências ficam no seu dispositivo. Não há conta para criar, nada é enviado e a aplicação não recolhe dados de análise. A contagem decrescente e a estimativa de ganhos são calculadas localmente.\n\nGratuita e de código aberto sob a licença MIT. O código completo está no GitHub, por isso cada afirmação desta página pode ser verificada no código.\n\nA interface da aplicação está disponível em 19 idiomas, incluindo português.",
    "releaseNotes": "Novidades da versão 3.1.9:\n\n• Página Atividade nas definições: dias trabalhados, horas com horas extra e toques no Woodfish, mês a mês. Fica tudo neste PC.\n• O Woodfish já conta para além de 999 e guarda os toques de cada dia.\n• O aumento do tamanho do texto no Windows deixou de ampliar a janela inteira.\n• Transições mais suaves entre páginas e pequenas correções.",
    "features": [
      "Contagem decrescente em direto na área de notificação",
      "Total opcional do que ganhou hoje",
      "Qualquer turno, incluindo noites que passam da meia-noite",
      "A pausa para almoço suspende a contagem",
      "As horas extra prolongam a contagem",
      "Lembretes aos 50%, 75%, 90% e 95%",
      "Lembretes opcionais para beber água e alongar",
      "Temporizador flutuante, sempre à frente",
      "Atalho global para mostrar ou ocultar a janela",
      "Iniciar com o Windows",
      "Funciona offline, sem conta",
      "Nada é enviado, sem análises",
      "Gratuito e de código aberto (MIT)",
      "Interface em 19 idiomas"
    ],
    "feature15": "Registo mensal: dias trabalhados, horas e toques no Woodfish",
    "searchTerms": [
      "contagem decrescente trabalho",
      "temporizador dia trabalho",
      "fim do turno",
      "horas de trabalho",
      "temporizador barra tarefas",
      "registo salário",
      "contador turno"
    ],
    "captions": [
      "Contagem decrescente",
      "Temporizador flutuante",
      "Atividade",
      "Horário",
      "Definições"
    ]
  },
  "ru": {
    "appLanguage": "ru",
    "isNewLanguage": true,
    "shortDescription": "Видно, сколько осталось до конца рабочего дня. Спокойный обратный отсчёт в области уведомлений и, если хотите, текущий заработок за день. Подходит для любых смен, включая ночные. Всё остаётся на вашем компьютере: без аккаунта и без отправки данных.",
    "description": "Смотрите, сколько именно осталось от вашего рабочего дня.\n\nDoneAt сводит смену к одному спокойному числу: сколько осталось, какая часть дня позади и — если хотите — сколько вы уже заработали, с точностью до секунды.\n\nНастройте график один раз. Обратный отсчёт живёт в области уведомлений, поэтому достаточно взгляда в угол экрана. Глобальное сочетание клавиш возвращает окно без поиска по вкладкам, а небольшой плавающий таймер может оставаться поверх работы, если число должно быть всегда перед глазами.\n\nПодходит для реальных графиков: с девяти до шести, смены по двенадцать часов или ночная смена после полуночи. Обед ставит счёт на паузу. Переработка продлевает его. Ненавязчивые напоминания подскажут, когда пройдена половина, когда осталось совсем немного и когда можно уходить; необязательные напоминания о здоровье предложат выпить воды или размяться.\n\nНовое в этой версии: страница «Статистика» с помесячным журналом — рабочие дни, часы с учётом переработок и сколько раз вы стукнули по Woodfish в плавающем таймере. Журнал, как и всё остальное, остаётся на этом ПК.\n\nВаш график, зарплата и настройки остаются на устройстве. Не нужно создавать аккаунт, ничего не загружается, приложение не собирает аналитику. Обратный отсчёт и оценка заработка считаются локально.\n\nБесплатное приложение с открытым исходным кодом под лицензией MIT. Полный исходный код — на GitHub, поэтому любое утверждение на этой странице можно проверить по коду.\n\nИнтерфейс приложения доступен на 19 языках, включая русский.",
    "releaseNotes": "Что нового в 3.1.9:\n\n• Страница «Статистика» в настройках: рабочие дни, часы с учётом переработок и удары по Woodfish по месяцам. Всё остаётся на этом ПК.\n• Счётчик Woodfish больше не останавливается на 999, удары за каждый день сохраняются.\n• Увеличение размера текста в Windows больше не растягивает всё окно.\n• Более плавные переходы между страницами и мелкие исправления.",
    "features": [
      "Обратный отсчёт в области уведомлений",
      "Необязательный подсчёт заработка за день",
      "Любые смены, включая ночные после полуночи",
      "Обед ставит счёт на паузу",
      "Переработка продлевает отсчёт",
      "Напоминания на 50%, 75%, 90% и 95%",
      "Необязательные напоминания попить воды и размяться",
      "Плавающий таймер поверх других окон",
      "Глобальное сочетание клавиш для показа и скрытия окна",
      "Запуск вместе с Windows",
      "Работает офлайн, без аккаунта",
      "Ничего не загружается, без аналитики",
      "Бесплатно и с открытым кодом (MIT)",
      "Интерфейс на 19 языках"
    ],
    "feature15": "Статистика по месяцам: рабочие дни, часы и удары по Woodfish",
    "searchTerms": [
      "таймер до конца работы",
      "обратный отсчёт смены",
      "счётчик рабочего времени",
      "таймер в трее",
      "учёт зарплаты",
      "конец рабочего дня"
    ],
    "captions": [
      "Обратный отсчёт",
      "Плавающий таймер",
      "Статистика",
      "График",
      "Настройки"
    ]
  },
  "hi": {
    "appLanguage": "hi-IN",
    "isNewLanguage": true,
    "shortDescription": "देखें कि आज का काम कितना बचा है। सूचना क्षेत्र में शांत काउंटडाउन, और चाहें तो आज की कमाई भी साथ में। हर तरह की शिफ़्ट पर चलता है, नाइट शिफ़्ट समेत। सब कुछ आपके PC पर ही रहता है — न खाता, न अपलोड।",
    "description": "देखें कि आज के काम का कितना हिस्सा बाकी है।\n\nDoneAt आपकी शिफ़्ट को एक शांत संख्या में बदल देता है: बचा हुआ समय, दिन कितना बीता, और चाहें तो अब तक की कमाई, जो हर सेकंड बढ़ती रहती है।\n\nकाम के घंटे एक बार तय करें। काउंटडाउन सूचना क्षेत्र में रहता है, इसलिए स्क्रीन के कोने पर एक नज़र काफ़ी है। ग्लोबल शॉर्टकट से विंडो वापस आ जाती है, ब्राउज़र टैब खोजने की ज़रूरत नहीं; और अगर संख्या हमेशा सामने चाहिए तो एक छोटा तैरता टाइमर काम के ऊपर टिका रह सकता है।\n\nयह असली शेड्यूल के हिसाब से चलता है: नौ से पाँच, बारह घंटे का दिन, या आधी रात के पार जाने वाली नाइट शिफ़्ट। लंच ब्रेक पर गिनती रुक जाती है, ओवरटाइम से बढ़ जाती है। हल्के रिमाइंडर बताते हैं कि आधा दिन हो गया, बस थोड़ा बचा है, और अब निकल सकते हैं; वैकल्पिक हेल्थ रिमाइंडर पानी पीने या उठकर टहलने की याद दिलाते हैं।\n\nइस वर्शन में नया: ‘गतिविधि’ पेज, जो हर महीने का रिकॉर्ड रखता है — काम के दिन, ओवरटाइम समेत घंटे, और मिनी टाइमर पर Woodfish कितनी बार बजाया। यह रिकॉर्ड भी बाकी सब की तरह इसी PC पर रहता है।\n\nआपके घंटे, वेतन और सेटिंग्स आपके डिवाइस पर ही रहते हैं। कोई खाता नहीं बनाना पड़ता, कुछ भी अपलोड नहीं होता, और ऐप कोई एनालिटिक्स नहीं जुटाता। काउंटडाउन और कमाई का अनुमान लोकल रूप से गिना जाता है।\n\nMIT लाइसेंस के तहत मुफ़्त और ओपन सोर्स। पूरा सोर्स कोड GitHub पर है, इसलिए इस पेज की हर बात कोड से मिलाकर देखी जा सकती है।\n\nऐप का इंटरफ़ेस 19 भाषाओं में उपलब्ध है, हिंदी सहित।",
    "releaseNotes": "3.1.9 में नया:\n\n• सेटिंग्स में ‘गतिविधि’ पेज: हर महीने के काम के दिन, ओवरटाइम समेत घंटे और Woodfish की ठोक। सब कुछ इसी PC पर रहता है।\n• Woodfish की गिनती अब 999 पर नहीं रुकती और हर दिन की ठोक सहेजी जाती है।\n• Windows में टेक्स्ट बड़ा करने की सेटिंग अब पूरी विंडो को नहीं बढ़ाती।\n• पेजों के बीच ज़्यादा सहज बदलाव और छोटे सुधार।",
    "features": [
      "सूचना क्षेत्र में लाइव काउंटडाउन",
      "आज की कमाई का वैकल्पिक जोड़",
      "हर शिफ़्ट, आधी रात के पार जाने वाली नाइट शिफ़्ट भी",
      "लंच ब्रेक पर गिनती रुकती है",
      "ओवरटाइम से काउंटडाउन बढ़ता है",
      "50%, 75%, 90% और 95% पर रिमाइंडर",
      "पानी और स्ट्रेच के वैकल्पिक रिमाइंडर",
      "तैरता मिनी टाइमर, हमेशा सबसे ऊपर",
      "विंडो दिखाने या छिपाने का ग्लोबल शॉर्टकट",
      "Windows के साथ शुरू",
      "ऑफ़लाइन चलता है, खाता ज़रूरी नहीं",
      "कुछ अपलोड नहीं, कोई एनालिटिक्स नहीं",
      "मुफ़्त और ओपन सोर्स (MIT)",
      "19 भाषाओं में इंटरफ़ेस"
    ],
    "feature15": "महीने का रिकॉर्ड: काम के दिन, घंटे और Woodfish की ठोक",
    "searchTerms": [
      "ऑफ़िस काउंटडाउन",
      "वर्कडे टाइमर",
      "शिफ़्ट काउंटडाउन टाइमर",
      "काम के घंटे ट्रैकर",
      "सिस्टम ट्रे टाइमर",
      "वर्क शिफ़्ट टाइमर",
      "सैलरी कमाई ट्रैकर"
    ],
    "captions": [
      "काउंटडाउन",
      "मिनी टाइमर",
      "गतिविधि",
      "काम के घंटे",
      "सेटिंग्स"
    ]
  },
  "mr": {
    "appLanguage": "mr-IN",
    "isNewLanguage": true,
    "shortDescription": "आजचं काम किती उरलंय ते नेमकं पाहा. सूचना क्षेत्रात शांत काउंटडाउन, आणि हवं असल्यास आजची कमाईसुद्धा. कोणत्याही शिफ्टसाठी चालतं, रात्रपाळीसह. सगळं तुमच्याच PC वर राहतं — खातं नाही, अपलोड नाही.",
    "description": "आजचं काम किती उरलंय, ते नेमकं पाहा.\n\nDoneAt तुमची शिफ्ट एका शांत आकड्यात मांडतं: उरलेला वेळ, दिवस किती सरला, आणि हवं असल्यास आतापर्यंतची कमाई, जी दर सेकंदाला वाढत राहते.\n\nकामाचे तास एकदाच ठरवा. काउंटडाउन सूचना क्षेत्रात राहतो, त्यामुळे स्क्रीनच्या कोपऱ्याकडे एक नजर पुरते. ग्लोबल शॉर्टकटने विंडो परत येते, ब्राउझर टॅब शोधावे लागत नाहीत; आणि आकडा सतत दिसावा असं वाटलं तर छोटा तरंगणारा टायमर कामाच्या वर ठेवता येतो.\n\nखऱ्या वेळापत्रकांना ते जुळतं: नऊ ते पाच, बारा तासांचा दिवस, किंवा मध्यरात्र ओलांडणारी रात्रपाळी. जेवणाच्या सुट्टीत मोजणी थांबते, ओव्हरटाइममध्ये वाढते. सौम्य स्मरणपत्रं सांगतात की अर्धा दिवस झाला, आता थोडंच उरलं, आणि आता निघायला हरकत नाही; ऐच्छिक आरोग्य स्मरणपत्रं पाणी प्यायची किंवा उठून उभं राहायची आठवण करून देतात.\n\nया आवृत्तीत नवीन: ‘आकडेवारी’ पान, जे महिन्याची नोंद ठेवतं — कामाचे दिवस, ओव्हरटाइमसह तास, आणि मिनी टायमरवर Woodfish किती वेळा वाजवला. ही नोंदसुद्धा बाकी सगळ्यासारखी याच PC वर राहते.\n\nतुमचे तास, पगार आणि प्राधान्यं तुमच्याच उपकरणावर राहतात. खातं तयार करावं लागत नाही, काहीही अपलोड होत नाही, आणि अॅप कोणतीही विश्लेषण माहिती गोळा करत नाही. काउंटडाउन आणि कमाईचा अंदाज स्थानिक पातळीवर मोजला जातो.\n\nMIT परवान्याअंतर्गत मोफत आणि ओपन सोर्स. संपूर्ण सोर्स कोड GitHub वर आहे, त्यामुळे या पानावरचं प्रत्येक विधान कोडशी ताडून पाहता येतं.\n\nअॅपचा इंटरफेस 19 भाषांमध्ये उपलब्ध आहे, मराठीसह.",
    "releaseNotes": "3.1.9 मध्ये नवीन:\n\n• सेटिंग्जमध्ये ‘आकडेवारी’ पान: दर महिन्याचे कामाचे दिवस, ओव्हरटाइमसह तास आणि Woodfish चे ठोके. सगळं याच PC वर राहतं.\n• Woodfish ची मोजणी आता 999 वर थांबत नाही आणि प्रत्येक दिवसाचे ठोके जतन होतात.\n• Windows मधील मजकूर मोठा करण्याच्या सेटिंगमुळे आता संपूर्ण विंडो मोठी होत नाही.\n• पानांमधील बदल अधिक सहज, आणि किरकोळ दुरुस्त्या.",
    "features": [
      "सूचना क्षेत्रात थेट काउंटडाउन",
      "आजच्या कमाईची ऐच्छिक बेरीज",
      "कोणतीही शिफ्ट, मध्यरात्र ओलांडणारी रात्रपाळीसुद्धा",
      "जेवणाच्या सुट्टीत मोजणी थांबते",
      "ओव्हरटाइममुळे काउंटडाउन वाढतो",
      "50%, 75%, 90% आणि 95% वर स्मरणपत्रं",
      "पाणी आणि स्ट्रेचसाठी ऐच्छिक स्मरणपत्रं",
      "तरंगणारा मिनी टायमर, नेहमी सर्वात वर",
      "विंडो दाखवण्या-लपवण्यासाठी ग्लोबल शॉर्टकट",
      "Windows सोबत सुरू",
      "ऑफलाइन चालतं, खात्याची गरज नाही",
      "काहीही अपलोड नाही, विश्लेषण नाही",
      "मोफत आणि ओपन सोर्स (MIT)",
      "19 भाषांमध्ये इंटरफेस"
    ],
    "feature15": "महिन्याची नोंद: कामाचे दिवस, तास आणि Woodfish चे ठोके",
    "searchTerms": [
      "ऑफिस काउंटडाउन",
      "वर्कडे टायमर",
      "शिफ्ट काउंटडाउन टायमर",
      "कामाचे तास ट्रॅकर",
      "सिस्टम ट्रे टायमर",
      "वर्क शिफ्ट टायमर",
      "पगार कमाई ट्रॅकर"
    ],
    "captions": [
      "काउंटडाउन",
      "मिनी टायमर",
      "आकडेवारी",
      "कामाचे तास",
      "सेटिंग्ज"
    ]
  },
  "tr": {
    "appLanguage": "tr",
    "isNewLanguage": true,
    "shortDescription": "Mesainizden ne kadar kaldığını tam olarak görün. Bildirim alanında sakin bir geri sayım ve isterseniz bugün kazandığınız tutar. Gece dahil her vardiyayla çalışır. Her şey bilgisayarınızda kalır: hesap yok, yükleme yok.",
    "description": "İş gününüzden ne kadar kaldığını tam olarak görün.\n\nDoneAt vardiyanızı tek bir sakin sayıya indirger: kalan süre, günün ne kadarının geçtiği ve isterseniz şu ana kadar kazandığınız tutar, saniye saniye artarak.\n\nMesai saatinizi bir kez ayarlayın. Geri sayım bildirim alanında durur; ekranın köşesine bakmanız yeter. Genel kısayol, sekmeler arasında aramadan pencereyi geri getirir; sayının hep görünmesini isterseniz küçük bir yüzen sayaç işinizin üstünde durabilir.\n\nGerçek çalışma düzenlerine uyar: dokuz-beş, on iki saatlik günler ya da gece yarısını geçen gece vardiyası. Öğle molası sayımı duraklatır, fazla mesai uzatır. Yumuşak hatırlatmalar yarıyı, sona yaklaştığınızı ve çıkabileceğinizi bildirir; isteğe bağlı sağlık hatırlatmaları su içmeyi ya da ayağa kalkmayı önerir.\n\nBu sürümde yeni: aylık kayıt tutan bir İstatistik sayfası — çalışılan günler, fazla mesai dahil saatler ve mini sayaçta Woodfish’e kaç kez vurduğunuz. Bu kayıt da diğer her şey gibi bu bilgisayarda kalır.\n\nSaatleriniz, maaşınız ve tercihleriniz cihazınızda kalır. Hesap açmanız gerekmez, hiçbir şey yüklenmez ve uygulama analiz verisi toplamaz. Geri sayım ve kazanç tahmini yerel olarak hesaplanır.\n\nMIT lisansıyla ücretsiz ve açık kaynak. Kaynak kodun tamamı GitHub’da, dolayısıyla bu sayfadaki her ifade kodla karşılaştırılabilir.\n\nUygulama arayüzü Türkçe dahil 19 dilde kullanılabilir.",
    "releaseNotes": "3.1.9 sürümündeki yenilikler:\n\n• Ayarlarda İstatistik sayfası: her ayın çalışılan günleri, fazla mesai dahil saatleri ve Woodfish vuruşları. Hepsi bu bilgisayarda kalır.\n• Woodfish sayacı artık 999’da durmuyor ve her günün vuruşları kaydediliyor.\n• Windows’taki metin büyütme ayarı artık pencerenin tamamını büyütmüyor.\n• Sayfalar arasında daha akıcı geçişler ve küçük düzeltmeler.",
    "features": [
      "Bildirim alanında canlı geri sayım",
      "İsteğe bağlı günlük kazanç toplamı",
      "Gece yarısını geçen geceler dahil her vardiya",
      "Öğle molası sayımı duraklatır",
      "Fazla mesai geri sayımı uzatır",
      "%50, %75, %90 ve %95’te hatırlatmalar",
      "İsteğe bağlı su ve esneme hatırlatmaları",
      "Her zaman üstte duran yüzen mini sayaç",
      "Pencereyi göstermek veya gizlemek için genel kısayol",
      "Windows ile birlikte başlatma",
      "Çevrimdışı çalışır, hesap gerekmez",
      "Hiçbir şey yüklenmez, analiz yok",
      "Ücretsiz ve açık kaynak (MIT)",
      "19 dilde arayüz"
    ],
    "feature15": "Aylık kayıt: çalışılan günler, saatler ve Woodfish vuruşları",
    "searchTerms": [
      "mesai geri sayım",
      "iş günü sayacı",
      "vardiya sayacı",
      "çalışma saati takibi",
      "bildirim alanı sayacı",
      "maaş takibi",
      "mesai bitiş"
    ],
    "captions": [
      "Geri sayım",
      "Mini sayaç",
      "İstatistik",
      "Mesai saatleri",
      "Ayarlar"
    ]
  },
  "ar": {
    "appLanguage": "ar",
    "isNewLanguage": true,
    "shortDescription": "اعرف بالضبط كم تبقى من يوم عملك. عد تنازلي هادئ في منطقة الإشعارات، مع إجمالي اختياري لما كسبته اليوم. يناسب أي وردية، بما فيها الليلية. كل شيء يبقى على جهازك: بلا حساب وبلا رفع للبيانات.",
    "description": "اعرف بالضبط كم تبقى من يوم عملك.\n\nيحوّل DoneAt ورديتك إلى رقم واحد هادئ: الوقت المتبقي، وكم مضى من اليوم، وإن أردت، ما كسبته حتى الآن وهو يتصاعد ثانية بثانية.\n\nاضبط ساعات عملك مرة واحدة. يبقى العد التنازلي في منطقة الإشعارات، فتكفي نظرة إلى زاوية الشاشة. ويعيد اختصار عام النافذة دون البحث بين علامات التبويب، ويمكن لمؤقت عائم صغير أن يبقى فوق عملك إذا أردت الرقم أمامك دائمًا.\n\nيناسب الجداول الحقيقية: من التاسعة إلى الخامسة، أو يوم من اثنتي عشرة ساعة، أو وردية ليلية تتجاوز منتصف الليل. تُوقف استراحة الغداء العد، ويمدّده العمل الإضافي. وتنبّهك تذكيرات لطيفة عند منتصف اليوم، وقبيل النهاية، وعند وقت الانصراف؛ أما تذكيرات الصحة الاختيارية فتقترح شرب الماء أو الوقوف قليلًا.\n\nالجديد في هذا الإصدار: صفحة «الإحصائيات» التي تحتفظ بسجل شهري — أيام العمل، والساعات مع العمل الإضافي، وكم مرة طرقت على Woodfish في المؤقت العائم. ويبقى هذا السجل على هذا الكمبيوتر، مثل كل شيء آخر.\n\nتبقى ساعات عملك وراتبك وتفضيلاتك على جهازك. لا حساب تنشئه، ولا شيء يُرفع، والتطبيق لا يجمع أي بيانات تحليلية. ويُحسب العد التنازلي وتقدير الأرباح محليًا.\n\nمجاني ومفتوح المصدر بترخيص MIT. الشيفرة الكاملة على GitHub، فكل ما في هذه الصفحة يمكن التحقق منه في الشيفرة.\n\nواجهة التطبيق متاحة بـ19 لغة، من بينها العربية.",
    "releaseNotes": "الجديد في الإصدار 3.1.9:\n\n• صفحة «الإحصائيات» في الإعدادات: أيام العمل، والساعات مع العمل الإضافي، وطرقات Woodfish لكل شهر. كل ذلك يبقى على هذا الكمبيوتر.\n• لم يعد عدّاد Woodfish يتوقف عند 999، وتُحفظ طرقات كل يوم.\n• لم يعد إعداد تكبير النص في Windows يكبّر النافذة بأكملها.\n• انتقالات أكثر سلاسة بين الصفحات وإصلاحات صغيرة.",
    "features": [
      "عد تنازلي مباشر في منطقة الإشعارات",
      "إجمالي اختياري لأرباح اليوم",
      "أي وردية، بما فيها الليلية بعد منتصف الليل",
      "استراحة الغداء توقف العد",
      "العمل الإضافي يمدّد العد التنازلي",
      "تذكيرات عند 50% و75% و90% و95%",
      "تذكيرات اختيارية لشرب الماء والتمدد",
      "مؤقت عائم يبقى فوق النوافذ",
      "اختصار عام لإظهار النافذة أو إخفائها",
      "التشغيل مع بدء Windows",
      "يعمل دون اتصال وبلا حساب",
      "لا يُرفع أي شيء، ولا تحليلات",
      "مجاني ومفتوح المصدر (MIT)",
      "واجهة بـ19 لغة"
    ],
    "feature15": "سجل شهري: أيام العمل والساعات وطرقات Woodfish",
    "searchTerms": [
      "عداد نهاية الدوام",
      "مؤقت يوم العمل",
      "عد تنازلي للوردية",
      "تتبع ساعات العمل",
      "مؤقت شريط المهام",
      "مؤقت الوردية",
      "تتبع الأرباح والراتب"
    ],
    "captions": [
      "العد التنازلي",
      "المؤقت العائم",
      "الإحصائيات",
      "ساعات العمل",
      "الإعدادات"
    ]
  },
  "th": {
    "appLanguage": "th",
    "isNewLanguage": true,
    "shortDescription": "ดูให้ชัดว่าวันทำงานเหลืออีกเท่าไร นับถอยหลังแบบเงียบ ๆ ในพื้นที่แจ้งเตือน พร้อมยอดรายได้ของวันนี้ถ้าต้องการ ใช้ได้กับทุกกะ รวมถึงกะดึก ทุกอย่างอยู่ในเครื่องของคุณ ไม่ต้องมีบัญชี ไม่มีการอัปโหลด",
    "description": "ดูให้ชัดว่าวันทำงานของคุณเหลืออีกเท่าไร\n\nDoneAt ย่อกะของคุณให้เหลือตัวเลขเดียวที่สงบ: เวลาที่เหลือ ผ่านไปแล้วเท่าไรของวัน และถ้าต้องการ ก็ดูรายได้จนถึงตอนนี้ที่เพิ่มขึ้นทีละวินาที\n\nตั้งเวลาทำงานครั้งเดียว ตัวนับถอยหลังอยู่ในพื้นที่แจ้งเตือน แค่ชำเลืองมองมุมจอก็พอ ปุ่มลัดส่วนกลางเรียกหน้าต่างกลับมาได้โดยไม่ต้องไล่หาแท็บ และถ้าอยากเห็นตัวเลขตลอดเวลา ก็ให้ตัวจับเวลาเล็ก ๆ ลอยอยู่เหนืองานได้\n\nรองรับตารางงานจริง: เก้าโมงถึงห้าโมง กะสิบสองชั่วโมง หรือกะดึกที่ข้ามเที่ยงคืน พักกลางวันจะหยุดนับ ทำโอทีจะต่อเวลาให้ การเตือนแบบเบา ๆ จะบอกเมื่อผ่านครึ่งทาง ใกล้เลิกงาน และเลิกได้แล้ว ส่วนการเตือนสุขภาพซึ่งเลือกเปิดได้ จะชวนให้ดื่มน้ำหรือลุกขึ้นยืด\n\nใหม่ในเวอร์ชันนี้: หน้า “สถิติ” ที่เก็บบันทึกรายเดือน ทั้งวันทำงาน ชั่วโมงรวมโอที และจำนวนครั้งที่เคาะ Woodfish บนตัวจับเวลาขนาดเล็ก บันทึกนี้อยู่ในเครื่องนี้เท่านั้น เหมือนข้อมูลอื่น ๆ\n\nเวลาทำงาน เงินเดือน และการตั้งค่าของคุณอยู่ในเครื่องของคุณ ไม่ต้องสร้างบัญชี ไม่มีการอัปโหลด และแอปไม่เก็บข้อมูลวิเคราะห์ใด ๆ การนับถอยหลังและการประมาณรายได้คำนวณในเครื่อง\n\nฟรีและโอเพนซอร์สภายใต้สัญญาอนุญาต MIT ซอร์สโค้ดทั้งหมดอยู่บน GitHub ทุกข้อความในหน้านี้จึงตรวจสอบกับโค้ดได้\n\nอินเทอร์เฟซของแอปมี 19 ภาษา รวมถึงภาษาไทย",
    "releaseNotes": "มีอะไรใหม่ใน 3.1.9:\n\n• หน้า “สถิติ” ในการตั้งค่า: วันทำงาน ชั่วโมงรวมโอที และจำนวนครั้งที่เคาะ Woodfish ของแต่ละเดือน ทุกอย่างอยู่ในเครื่องนี้เท่านั้น\n• ตัวนับ Woodfish ไม่หยุดที่ 999 อีกต่อไป และบันทึกจำนวนครั้งของแต่ละวัน\n• การตั้งค่าขยายขนาดตัวอักษรของ Windows ไม่ทำให้ทั้งหน้าต่างใหญ่ขึ้นอีกต่อไป\n• การเปลี่ยนหน้าลื่นไหลขึ้น และแก้ไขปัญหาเล็กน้อย",
    "features": [
      "นับถอยหลังแบบเรียลไทม์ในพื้นที่แจ้งเตือน",
      "ยอดรายได้ของวันนี้ (เลือกเปิดได้)",
      "ทุกกะ รวมถึงกะดึกที่ข้ามเที่ยงคืน",
      "พักกลางวันจะหยุดนับ",
      "ทำโอทีจะต่อเวลานับถอยหลัง",
      "เตือนเมื่อถึง 50%, 75%, 90% และ 95%",
      "เตือนดื่มน้ำและยืดเส้น (เลือกเปิดได้)",
      "ตัวจับเวลาลอยอยู่เหนือหน้าต่างอื่นเสมอ",
      "ปุ่มลัดส่วนกลางสำหรับแสดงหรือซ่อนหน้าต่าง",
      "เปิดพร้อม Windows",
      "ใช้ออฟไลน์ได้ ไม่ต้องมีบัญชี",
      "ไม่อัปโหลดข้อมูล ไม่เก็บสถิติการใช้งาน",
      "ฟรีและโอเพนซอร์ส (MIT)",
      "อินเทอร์เฟซ 19 ภาษา"
    ],
    "feature15": "บันทึกรายเดือน: วันทำงาน ชั่วโมง และจำนวนครั้งที่เคาะ Woodfish",
    "searchTerms": [
      "นับถอยหลังเลิกงาน",
      "ตัวจับเวลาวันทำงาน",
      "นับถอยหลังกะทำงาน",
      "ติดตามชั่วโมงทำงาน",
      "ตัวจับเวลาถาดระบบ",
      "ตัวจับเวลากะ",
      "ติดตามรายได้เงินเดือน"
    ],
    "captions": [
      "นับถอยหลัง",
      "ตัวจับเวลาขนาดเล็ก",
      "สถิติ",
      "เวลาทำงาน",
      "การตั้งค่า"
    ]
  },
  "id-id": {
    "appLanguage": "id",
    "isNewLanguage": true,
    "shortDescription": "Lihat persis berapa sisa hari kerja Anda. Hitung mundur yang tenang di area notifikasi, dengan total penghasilan hari ini bila diinginkan. Cocok untuk semua sif, termasuk sif malam. Semuanya tetap di perangkat Anda: tanpa akun, tanpa unggahan.",
    "description": "Lihat persis berapa sisa hari kerja Anda.\n\nDoneAt meringkas sif Anda menjadi satu angka yang tenang: sisa waktu, sudah sejauh mana hari berjalan, dan — jika Anda mau — penghasilan sampai saat ini, yang bertambah tiap detik.\n\nAtur jam kerja sekali saja. Hitung mundur tinggal di area notifikasi, jadi cukup melirik sudut layar. Pintasan global memanggil kembali jendelanya tanpa mengaduk-aduk tab, dan timer mengambang kecil bisa tetap berada di atas pekerjaan Anda jika ingin angkanya selalu terlihat.\n\nCocok untuk jadwal nyata: jam sembilan sampai lima, hari kerja dua belas jam, atau sif malam yang lewat tengah malam. Istirahat makan siang menjeda hitungan, lembur memperpanjangnya. Pengingat yang lembut memberi tahu saat setengah jalan, hampir selesai, dan sudah boleh pulang; pengingat kesehatan opsional mengajak Anda minum air atau berdiri sejenak.\n\nBaru di versi ini: halaman Aktivitas yang menyimpan catatan bulanan — hari kerja, jam kerja termasuk lembur, dan berapa kali Anda mengetuk Woodfish di timer mini. Catatan itu tetap di PC ini, seperti yang lain.\n\nJam kerja, gaji, dan preferensi Anda tetap di perangkat Anda. Tidak ada akun yang perlu dibuat, tidak ada yang diunggah, dan aplikasi tidak mengumpulkan data analitik. Hitung mundur dan perkiraan penghasilan dihitung secara lokal.\n\nGratis dan sumber terbuka dengan lisensi MIT. Seluruh kode sumbernya ada di GitHub, sehingga setiap klaim di halaman ini bisa dicocokkan dengan kodenya.\n\nAntarmuka aplikasi tersedia dalam 19 bahasa, termasuk bahasa Indonesia.",
    "releaseNotes": "Yang baru di 3.1.9:\n\n• Halaman Aktivitas di pengaturan: hari kerja, jam kerja termasuk lembur, dan ketukan Woodfish setiap bulan. Semuanya tetap di PC ini.\n• Hitungan Woodfish kini melewati 999, dan ketukan setiap hari tersimpan.\n• Pengaturan perbesaran teks Windows tidak lagi memperbesar seluruh jendela.\n• Perpindahan halaman lebih mulus dan perbaikan kecil.",
    "features": [
      "Hitung mundur langsung di area notifikasi",
      "Total penghasilan hari ini (opsional)",
      "Semua sif, termasuk malam yang lewat tengah malam",
      "Istirahat makan siang menjeda hitungan",
      "Lembur memperpanjang hitung mundur",
      "Pengingat di 50%, 75%, 90%, dan 95%",
      "Pengingat minum air dan peregangan (opsional)",
      "Timer mengambang, selalu di atas",
      "Pintasan global untuk menampilkan atau menyembunyikan jendela",
      "Jalankan bersama Windows",
      "Bekerja offline, tanpa akun",
      "Tidak ada yang diunggah, tanpa analitik",
      "Gratis dan sumber terbuka (MIT)",
      "Antarmuka dalam 19 bahasa"
    ],
    "feature15": "Catatan bulanan: hari kerja, jam kerja, dan ketukan Woodfish",
    "searchTerms": [
      "hitung mundur kerja",
      "timer hari kerja",
      "hitung mundur sif",
      "pelacak jam kerja",
      "timer baki sistem",
      "pelacak gaji",
      "jam pulang"
    ],
    "captions": [
      "Hitung mundur",
      "Timer mini",
      "Aktivitas",
      "Jam kerja",
      "Pengaturan"
    ]
  },
  "vi": {
    "appLanguage": "vi",
    "isNewLanguage": true,
    "shortDescription": "Biết chính xác ngày làm việc còn lại bao nhiêu. Đồng hồ đếm ngược lặng lẽ trong khay hệ thống, kèm số tiền kiếm được hôm nay nếu bạn muốn. Dùng được cho mọi ca, kể cả ca đêm. Mọi thứ nằm trên máy của bạn — không tài khoản, không tải lên.",
    "description": "Biết chính xác ngày làm việc của bạn còn lại bao nhiêu.\n\nDoneAt rút gọn ca làm của bạn thành một con số điềm tĩnh: thời gian còn lại, đã đi được bao xa trong ngày, và nếu bạn muốn, số tiền kiếm được tới lúc này, nhích lên từng giây.\n\nĐặt giờ làm một lần. Đồng hồ đếm ngược nằm ở khay hệ thống, chỉ cần liếc góc màn hình là đủ. Phím tắt toàn cục gọi lại cửa sổ mà không phải lục tìm giữa các thẻ trình duyệt, còn bộ hẹn giờ nhỏ có thể nổi trên công việc nếu bạn muốn luôn thấy con số.\n\nNó hợp với lịch làm thật: chín giờ đến năm giờ, ca mười hai tiếng, hay ca đêm qua nửa đêm. Giờ nghỉ trưa tạm dừng đếm, tăng ca kéo dài thêm. Những nhắc nhở nhẹ nhàng cho biết khi đã nửa chặng, sắp xong, và có thể về; nhắc nhở sức khỏe tùy chọn thì gợi ý uống nước hoặc đứng dậy vươn vai.\n\nMới trong phiên bản này: trang Thống kê lưu nhật ký theo tháng — số ngày làm, giờ làm tính cả tăng ca, và số lần bạn gõ mõ trên bộ hẹn giờ nhỏ. Nhật ký đó nằm trên máy này, như mọi thứ khác.\n\nGiờ làm, lương và tùy chọn của bạn nằm trên máy bạn. Không phải tạo tài khoản, không có gì được tải lên, và ứng dụng không thu thập dữ liệu phân tích. Đồng hồ đếm ngược và ước tính thu nhập đều được tính cục bộ.\n\nMiễn phí và mã nguồn mở theo giấy phép MIT. Toàn bộ mã nguồn nằm trên GitHub, nên mọi điều nói ở trang này đều có thể đối chiếu với mã.\n\nGiao diện ứng dụng có 19 ngôn ngữ, bao gồm tiếng Việt.",
    "releaseNotes": "Có gì mới trong 3.1.9:\n\n• Trang Thống kê trong cài đặt: số ngày làm, giờ làm tính cả tăng ca và số lần gõ mõ của từng tháng. Mọi thứ nằm trên máy này.\n• Bộ đếm mõ không còn dừng ở 999 và lưu lại số lần gõ mỗi ngày.\n• Thiết lập phóng to chữ của Windows không còn làm phóng to cả cửa sổ.\n• Chuyển trang mượt hơn và sửa một số lỗi nhỏ.",
    "features": [
      "Đếm ngược trực tiếp trong khay hệ thống",
      "Tùy chọn hiển thị thu nhập hôm nay",
      "Mọi ca làm, kể cả ca đêm qua nửa đêm",
      "Giờ nghỉ trưa tạm dừng đếm",
      "Tăng ca kéo dài đếm ngược",
      "Nhắc nhở ở mốc 50%, 75%, 90% và 95%",
      "Tùy chọn nhắc uống nước và vươn vai",
      "Bộ hẹn giờ nhỏ luôn nổi trên cùng",
      "Phím tắt toàn cục để hiện hoặc ẩn cửa sổ",
      "Khởi chạy cùng Windows",
      "Chạy ngoại tuyến, không cần tài khoản",
      "Không tải lên gì, không thu thập dữ liệu",
      "Miễn phí và mã nguồn mở (MIT)",
      "Giao diện 19 ngôn ngữ"
    ],
    "feature15": "Nhật ký hằng tháng: số ngày làm, giờ làm và số lần gõ mõ",
    "searchTerms": [
      "đếm ngược tan làm",
      "hẹn giờ làm việc",
      "đếm ngược ca",
      "theo dõi giờ làm",
      "hẹn giờ khay",
      "theo dõi lương"
    ],
    "captions": [
      "Đếm ngược",
      "Bộ hẹn giờ nhỏ",
      "Thống kê",
      "Giờ làm",
      "Cài đặt"
    ]
  },
  "zh-hant-hk": {
    "appLanguage": "zh-HK",
    "isNewLanguage": true,
    "shortDescription": "一眼看清今天還剩多少工作時間。這是一款安靜的系統匣倒數計時工具，可選即時顯示今天已賺取的收入。適用於任何班次，包括夜班。所有內容都保留在你的裝置上——無需帳戶，也不會上傳資料。",
    "description": "一眼看清今天還剩多少工作時間。\n\nDoneAt 將你的班次化作一個安靜清晰的數字：剩餘時間、今天已過的進度，以及——如果你願意——截至此刻的收入，按秒即時增加。\n\n只需設定一次工作時間。倒數計時會常駐在系統匣，瞥一眼螢幕角落就夠了。透過全域快速鍵，無需在瀏覽器分頁中翻找即可重新開啟視窗；如果你希望數字始終可見，也可以讓小型懸浮計時器置於工作內容之上。\n\n它適配真實的排班：朝九晚五、十二小時工作日，或跨越午夜的夜班。午休會暫停倒數計時，加班會延長倒數計時。溫和的提醒會在過半、快結束以及可以下班時告訴你；可選的健康提醒則會提示你喝水或起身活動。\n\n本次新增「統計」頁：按月記錄出勤天數、含加班的工時，以及在迷你計時器上敲木魚的次數。這些記錄和其他資料一樣，只儲存在這部電腦上。\n\n你的工時、薪資與偏好均保留在裝置上。無需建立帳戶，不會上傳任何內容，應用程式也不會收集分析資料。倒數計時和收入估算均在本機計算。\n\n基於 MIT 授權條款免費開源。完整原始碼託管在 GitHub，因此本頁中的每一項說明都可以對照程式碼核實。\n\n應用程式介面提供 19 種語言，包括繁體中文。",
    "releaseNotes": "3.1.9 更新內容：\n\n• 設定裡新增「統計」頁：按月查看出勤天數、含加班的工時和敲木魚的次數，資料只儲存在這部電腦上。\n• 木魚計數不再停在 999，每天敲了幾下都會記下來。\n• Windows 的文字放大設定不再把整個視窗一起放大。\n• 頁面切換更順暢，並修正了一些小問題。",
    "features": [
      "系統匣中的即時倒數計時",
      "可選即時累計顯示今日收入",
      "適用於任何班次，包括跨越午夜的夜班",
      "午休會暫停倒數計時",
      "加班會延長倒數計時",
      "在 50%、75%、90% 和 95% 時發送里程碑提醒",
      "可選的喝水和伸展提醒",
      "始終置頂的懸浮迷你計時器",
      "用於顯示或隱藏視窗的全域快速鍵",
      "開機自動啟動",
      "支援離線使用，無需帳戶",
      "不會上傳任何內容，也不收集分析資料",
      "免費開源（MIT）",
      "提供 19 種介面語言"
    ],
    "feature15": "統計頁：按月記錄出勤天數、工時和木魚次數",
    "searchTerms": [
      "下班倒數",
      "工作日計時器",
      "班次倒數計時器",
      "工時追蹤器",
      "系統匣計時器",
      "工作班次計時器",
      "薪資收入追蹤器"
    ],
    "captions": [
      "倒數計時",
      "迷你計時器",
      "統計",
      "上下班時間",
      "設定"
    ]
  }
};
