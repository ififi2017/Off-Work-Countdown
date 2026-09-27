// Chrome 应用商店每种语言的截图文案和详细说明。compose.mjs 用它排截图，并把说明写成
// out/<商店语言>/description.txt，照着文件夹逐个语言粘贴、上传即可。
//
// 键是应用界面语言（截图按它截），`store` 是开发者后台里对应的商店语言。zh-HK 没有
// 对应的商店语言，不在这里。标题和一句话简介不在这里：它们在扩展包里
// （src-extension/copy.json 的 extensionName / extensionSummary）。
//
// 口吻跟随各语言现有商品页（德语 Sie、法语 vous、土耳其语 siz、印尼语 Anda），
// 按钮与主题名引用应用内译文。说明里的每一条都必须对弹窗成立：不申请权限、不联网、
// 不在后台运行、数据只在这台浏览器里。

export const SHOTS = [
  ["countdown"],
  ["setup"],
  ["settings"],
  ["countdown-dark", "countdown-sunset"],
];

export const LISTINGS = {
  en: {
    store: "en",
    captions: [
      { title: "Know when your time is yours", sub: "One click on the toolbar shows the time left, how far through the day you are and what you have earned so far." },
      { title: "Set your hours once", sub: "Pick your hours and workdays. Lunch pauses the clock, and night shifts that run past midnight count correctly." },
      { title: "Your numbers stay with you", sub: "No account to create. Hours, pay and preferences are saved in this browser, and nothing is sent anywhere." },
      { title: "Make it feel like yours", sub: "Light, Dark, Sunset and Cyberpunk themes in 19 languages. Works offline." },
    ],
    description: `Know exactly when your workday ends, without keeping a tab open.

DoneAt puts a calm countdown to clock-off in your Chrome toolbar. Click the icon and you can see at a glance how much of the day is left, how far through it you are and, if you like, what you have earned so far. It is made for anyone who has ever asked "how long until I can go home?" and wanted a straight answer.

WHY INSTALL IT

• One click from any tab
There is no website to open and no app to switch to. Whatever you are working on, the answer is one click away, and closing the popup takes you straight back.

• It fits the way you actually work
Set your start and end times and your workdays once. Lunch breaks pause the countdown, night shifts that run past midnight are counted correctly, and before your shift or on a day off, DoneAt counts down to the next one.

• Watch the day add up
Add a monthly or daily salary and see today's earnings grow second by second, along with estimates for this week and this year. One tap hides the amount when someone is looking over your shoulder.

• Private by design
Your hours, salary and preferences are saved only in this browser. There is no account to create, no analytics and nothing is sent anywhere. DoneAt asks for no permissions, so it cannot read the pages you visit.

• Light and quiet
Nothing runs in the background. DoneAt works everything out from the clock each time you open it, so it uses no memory or battery between glances, and it works offline.

• Make it yours
Choose Light, Dark, Sunset or Cyberpunk, or follow your system. Available in 19 languages.

GETTING STARTED

1. Open the Extensions menu (the puzzle icon) and pin DoneAt to your toolbar.
2. Set your start and end times and your workdays, then press Start Countdown.
3. Click the icon whenever you want to check. Lunch breaks and salary live in Settings.

WANT IT OUTSIDE THE BROWSER TOO?

DoneAt is also available for Mac and Windows, where the time left stays in your menu bar or system tray, and for iPhone and iPad, with Home Screen widgets and support for rotating shifts. The Get the app button in Settings takes you to doneat.app.

DoneAt is open source, so you can read exactly what it does on GitHub.`,
  },

  "zh-CN": {
    store: "zh_CN",
    captions: [
      { title: "几点下班，\n心里有数", sub: "点一下工具栏，就能看到剩余时间、\n今天的进度和已经挣到的钱。" },
      { title: "上下班时间\n只需设置一次", sub: "选好上下班时间和工作日。\n午休自动暂停，跨过午夜的夜班也算得对。" },
      { title: "数据只留在\n你的浏览器里", sub: "不用注册账号。\n作息、薪资和偏好都存在这台浏览器里，\n不会发送到任何地方。" },
      { title: "换成你喜欢的样子", sub: "浅色、深色、日落和赛博朋克四种主题，\n支持 19 种语言，离线也能用。" },
    ],
    description: `几点下班，心里有数，不用一直开着网页。

DoneAt 把下班倒计时放进 Chrome 工具栏。点一下图标，就能看到今天还剩多少时间、已经完成了多少，想看的话，还能看到今天已经挣了多少钱。每一个在工位上想过「还有多久能走」的人，都可以用它得到一个清清楚楚的答案。

为什么值得装

• 在任何标签页，点一下就能看
不用打开网站，也不用切换应用。无论手上在忙什么，答案都只差一次点击；关掉弹窗就回到原来的页面。

• 贴合你真实的上班方式
上下班时间和工作日只需设置一次。午休时倒计时自动暂停，跨过午夜的夜班也算得对；还没上班或者休息日，会自动倒数到下一个班次。

• 看着今天一点点攒起来
填上月薪或日薪，就能看到今日已赚按秒增长，还有本周和今年的估算。有人从身后路过时，点一下就能把金额藏起来。

• 隐私放在第一位
作息、薪资和偏好只存在这台浏览器里。不用注册账号，没有统计上报，也不会把任何数据发送出去。DoneAt 不申请任何权限，所以读不到你浏览的网页。

• 轻巧安静
不在后台运行。每次打开时根据当前时间算好一切，没打开的时候不占内存、不耗电，断网也能用。

• 换成你喜欢的样子
浅色、深色、日落、赛博朋克四种主题，也可以跟随系统；支持 19 种语言。

三步开始

1. 打开扩展程序菜单（拼图图标），把 DoneAt 固定到工具栏。
2. 设置上下班时间和工作日，点「开始倒计时」。
3. 想看的时候点一下图标就好。午休和薪资在设置里调整。

想在浏览器之外也能看到？

DoneAt 也有 Mac 和 Windows 版，剩余时间常驻菜单栏或系统托盘；还有 iPhone 和 iPad 版，桌面小组件抬眼就能看，轮班、倒班也能排好。设置里的「获取 App」会带你去 doneat.app。

DoneAt 是开源软件，它做了什么、没做什么，都可以在 GitHub 上看得清清楚楚。`,
  },

  "zh-TW": {
    store: "zh_TW",
    captions: [
      { title: "幾點下班，\n心裡有數", sub: "點一下工具列，就能看到剩餘時間、\n今天的進度和已經賺到的錢。" },
      { title: "上下班時間\n只需設定一次", sub: "選好上下班時間和工作日。\n午休自動暫停，跨過午夜的夜班也算得對。" },
      { title: "資料只留在\n你的瀏覽器裡", sub: "不用註冊帳號。\n作息、薪資和偏好都存在這台瀏覽器裡，\n不會傳送到任何地方。" },
      { title: "換成你喜歡的樣子", sub: "淺色、深色、日落和賽博龐克四種主題，\n支援 19 種語言，離線也能用。" },
    ],
    description: `幾點下班，心裡有數，不用一直開著網頁。

DoneAt 把下班倒數計時放進 Chrome 工具列。點一下圖示，就能看到今天還剩多少時間、已經完成了多少；想看的話，還能看到今天已經賺了多少錢。每一個在座位上想過「還有多久能走」的人，都可以用它得到一個清清楚楚的答案。

為什麼值得安裝

• 在任何分頁，點一下就能看
不用打開網站，也不用切換應用程式。無論手上在忙什麼，答案都只差一次點擊；關掉彈出視窗就回到原本的頁面。

• 貼合你真實的上班方式
上下班時間和工作日只需設定一次。午休時倒數自動暫停，跨過午夜的夜班也算得對；還沒上班或遇到休息日，會自動倒數到下一個班次。

• 看著今天一點一點累積
填上月薪或日薪，就能看到今日已賺按秒增加，還有本週和今年的估算。有人從身後經過時，點一下就能把金額藏起來。

• 隱私放在第一位
作息、薪資和偏好只存在這台瀏覽器裡。不用註冊帳號，沒有統計回報，也不會把任何資料傳送出去。DoneAt 不要求任何權限，所以讀不到你瀏覽的網頁。

• 輕巧安靜
不在背景執行。每次打開時根據當下時間算好一切，沒打開的時候不佔記憶體、不耗電，離線也能用。

• 換成你喜歡的樣子
淺色、深色、日落、賽博龐克四種主題，也可以跟隨系統；支援 19 種語言。

三步開始

1. 打開擴充功能選單（拼圖圖示），把 DoneAt 固定到工具列。
2. 設定上下班時間和工作日，點「開始倒數計時」。
3. 想看的時候點一下圖示就好。午休和薪資在設定裡調整。

想在瀏覽器之外也能看到？

DoneAt 也有 Mac 和 Windows 版，剩餘時間常駐選單列或系統匣；還有 iPhone 和 iPad 版，主畫面小工具抬眼就能看，輪班、排班也能處理。設定裡的「取得 App」會帶你前往 doneat.app。

DoneAt 是開源軟體，它做了什麼、沒做什麼，都能在 GitHub 上看得清清楚楚。`,
  },

  ja: {
    store: "ja",
    captions: [
      { title: "退勤まで、\nあとどれくらい", sub: "ツールバーをワンクリック。\n残り時間、今日の進み具合、\nここまでの収入がわかります。" },
      { title: "勤務時間の設定は\n一度だけ", sub: "勤務時間と勤務日を選ぶだけ。\n昼休みは自動で一時停止、\n日付をまたぐ夜勤も正しく計算します。" },
      { title: "データは\nブラウザの中だけ", sub: "アカウント登録は不要です。\n勤務時間・給与・設定は\nこのブラウザに保存され、\nどこにも送信されません。" },
      { title: "好きな見た目で", sub: "ライト、ダーク、サンセット、\nサイバーパンクの4つのテーマ。\n19言語対応、オフラインでも使えます。" },
    ],
    description: `退勤まであとどれくらいか、タブを開いておかなくてもすぐにわかります。

DoneAt は Chrome のツールバーに退勤までのカウントダウンを置く拡張機能です。アイコンをクリックすれば、今日の残り時間、どこまで進んだか、そして必要なら今日ここまでに稼いだ金額がひと目でわかります。「あと何時間で帰れるんだろう」と思ったことのあるすべての人に、はっきりした答えを届けます。

インストールしたくなる理由

• どのタブからでもワンクリック
サイトを開く必要も、アプリを切り替える必要もありません。何をしていても答えはワンクリック先。ポップアップを閉じれば、すぐ元のページに戻れます。

• 実際の働き方にぴったり
勤務時間と勤務日の設定は一度だけ。昼休み中はカウントダウンが一時停止し、日付をまたぐ夜勤も正しく計算します。勤務前や休日には、次の勤務までをカウントダウンします。

• 今日の稼ぎが増えていくのを見る
月給または日給を入力すると、今日の収入が1秒ごとに増えていく様子と、今週・今年の見込みが表示されます。誰かが後ろを通ったら、ワンタップで金額を隠せます。

• プライバシーを最優先に
勤務時間・給与・設定はこのブラウザの中だけに保存されます。アカウント登録も、利用状況の収集もなく、データはどこにも送信されません。DoneAt は権限を一切求めないため、閲覧中のページを読み取ることもできません。

• 軽くて静か
バックグラウンドでは何も動きません。開くたびに現在時刻からすべてを計算するので、見ていない間はメモリもバッテリーも使わず、オフラインでも動きます。

• 好きな見た目で
ライト、ダーク、サンセット、サイバーパンクから選べるほか、システム設定にも合わせられます。19言語に対応しています。

はじめかた

1. 拡張機能メニュー（パズルのアイコン）を開き、DoneAt をツールバーに固定します。
2. 勤務開始・終了の時刻と勤務日を設定し、「カウントダウン開始」を押します。
3. 知りたいときにアイコンをクリックするだけ。昼休みと給与は設定から変更できます。

ブラウザの外でも見たいなら

DoneAt には Mac・Windows 版もあり、残り時間をメニューバーやシステムトレイに常に表示できます。iPhone・iPad 版ではホーム画面のウィジェットで確認でき、シフト勤務にも対応しています。設定の「アプリを入手」から doneat.app に移動できます。

DoneAt はオープンソースです。何をしていて何をしていないのか、GitHub ですべて確認できます。`,
  },

  ko: {
    store: "ko",
    captions: [
      { title: "퇴근까지\n얼마나 남았는지", sub: "툴바를 한 번 누르면 남은 시간과 오늘의 진행률,\n지금까지 번 돈을 바로 볼 수 있어요." },
      { title: "근무 시간은\n한 번만 설정", sub: "근무 시간과 근무일만 고르면 끝. 점심시간에는\n자동으로 멈추고, 자정을 넘기는 야간 근무도 정확히 계산해요." },
      { title: "데이터는\n이 브라우저에만", sub: "가입할 필요가 없어요. 근무 시간, 급여, 설정은\n이 브라우저에만 저장되고 어디에도 전송되지 않아요." },
      { title: "원하는 모습으로", sub: "라이트, 다크, 선셋, 사이버펑크 네 가지 테마.\n19개 언어를 지원하고 오프라인에서도 쓸 수 있어요." },
    ],
    description: `퇴근까지 얼마나 남았는지, 탭을 열어 두지 않아도 바로 알 수 있어요.

DoneAt은 Chrome 툴바에 퇴근 카운트다운을 올려 두는 확장 프로그램이에요. 아이콘을 누르면 오늘 남은 시간과 진행률, 원한다면 지금까지 번 돈까지 한눈에 보여요. "언제 집에 갈 수 있지?" 하고 생각해 본 적 있는 모든 분께 분명한 답을 드려요.

설치해야 하는 이유

• 어떤 탭에서든 한 번 클릭
웹사이트를 열 필요도, 앱을 바꿀 필요도 없어요. 무엇을 하고 있든 답은 클릭 한 번 거리에 있고, 팝업을 닫으면 바로 원래 페이지로 돌아가요.

• 실제로 일하는 방식에 맞게
출퇴근 시간과 근무일은 한 번만 설정하면 돼요. 점심시간에는 카운트다운이 멈추고, 자정을 넘기는 야간 근무도 정확히 계산해요. 출근 전이나 쉬는 날에는 다음 근무까지 카운트다운해요.

• 오늘 번 돈이 쌓이는 걸 보세요
월급이나 일급을 입력하면 오늘 번 돈이 1초마다 늘어나는 모습과 이번 주, 올해 예상치를 함께 보여 줘요. 누가 뒤로 지나갈 때는 한 번 눌러 금액을 숨길 수 있어요.

• 개인정보가 먼저
근무 시간, 급여, 설정은 이 브라우저에만 저장돼요. 가입도, 사용 통계 수집도 없고 어떤 데이터도 밖으로 보내지 않아요. DoneAt은 어떤 권한도 요청하지 않아서 보고 있는 웹페이지를 읽을 수 없어요.

• 가볍고 조용하게
백그라운드에서 아무것도 실행하지 않아요. 열 때마다 현재 시각으로 모든 걸 계산하기 때문에, 보지 않는 동안에는 메모리와 배터리를 쓰지 않고 오프라인에서도 작동해요.

• 원하는 모습으로
라이트, 다크, 선셋, 사이버펑크 중에서 고르거나 시스템 설정을 따를 수 있어요. 19개 언어를 지원해요.

시작하기

1. 확장 프로그램 메뉴(퍼즐 아이콘)를 열고 DoneAt을 툴바에 고정하세요.
2. 출퇴근 시간과 근무일을 설정한 뒤 "카운트다운 시작"을 누르세요.
3. 궁금할 때마다 아이콘을 누르면 끝. 점심시간과 급여는 설정에서 바꿀 수 있어요.

브라우저 밖에서도 보고 싶다면

DoneAt은 Mac과 Windows에서도 쓸 수 있어요. 남은 시간이 메뉴 막대나 시스템 트레이에 늘 떠 있어요. iPhone과 iPad 앱에서는 홈 화면 위젯으로 보고, 교대 근무도 관리할 수 있어요. 설정의 "앱 받기"를 누르면 doneat.app으로 이동해요.

DoneAt은 오픈 소스예요. 무엇을 하고 무엇을 하지 않는지 GitHub에서 모두 확인할 수 있어요.`,
  },

  de: {
    store: "de",
    captions: [
      { title: "Wissen, wann Feierabend ist", sub: "Ein Klick in der Symbolleiste zeigt die verbleibende Zeit, den Fortschritt und was Sie heute schon verdient haben." },
      { title: "Arbeitszeiten einmal festlegen", sub: "Zeiten und Arbeitstage wählen – fertig. Die Mittagspause hält die Uhr an, Nachtschichten über Mitternacht werden richtig gezählt." },
      { title: "Ihre Zahlen bleiben bei Ihnen", sub: "Kein Konto nötig. Zeiten, Gehalt und Einstellungen bleiben in diesem Browser, und nichts wird irgendwohin gesendet." },
      { title: "Ganz nach Ihrem Geschmack", sub: "Die Designs Hell, Dunkel, Sonnenuntergang und Cyberpunk, in 19 Sprachen. Funktioniert auch offline." },
    ],
    description: `Wissen, wann Feierabend ist – ohne einen Tab offen zu halten.

DoneAt bringt einen ruhigen Countdown bis zum Feierabend in Ihre Chrome-Symbolleiste. Ein Klick auf das Symbol zeigt auf einen Blick, wie viel vom Tag noch übrig ist, wie weit Sie schon sind und – wenn Sie möchten – was Sie heute bereits verdient haben. Für alle, die sich schon einmal gefragt haben: „Wie lange noch, bis ich nach Hause kann?“

WARUM SIE ES INSTALLIEREN SOLLTEN

• Ein Klick aus jedem Tab
Keine Website öffnen, keine App wechseln. Woran Sie auch arbeiten, die Antwort ist einen Klick entfernt, und nach dem Schließen sind Sie sofort wieder auf Ihrer Seite.

• Passt zu Ihrem echten Arbeitsalltag
Beginn, Ende und Arbeitstage legen Sie einmal fest. In der Mittagspause pausiert der Countdown, Nachtschichten über Mitternacht werden richtig gezählt, und vor Schichtbeginn oder an freien Tagen zählt DoneAt bis zur nächsten Schicht.

• Sehen, wie der Tag sich lohnt
Tragen Sie ein Monats- oder Tagesgehalt ein und sehen Sie, wie Ihr heutiger Verdienst Sekunde für Sekunde wächst – dazu Schätzungen für diese Woche und dieses Jahr. Ein Tipp blendet den Betrag aus, wenn Ihnen jemand über die Schulter schaut.

• Privatsphäre von Anfang an
Zeiten, Gehalt und Einstellungen werden nur in diesem Browser gespeichert. Kein Konto, keine Statistik, nichts wird irgendwohin gesendet. DoneAt fordert keinerlei Berechtigungen an und kann die Seiten, die Sie besuchen, daher nicht lesen.

• Leicht und leise
Im Hintergrund läuft nichts. DoneAt berechnet alles beim Öffnen aus der aktuellen Uhrzeit, braucht zwischendurch weder Speicher noch Akku und funktioniert auch offline.

• Ganz nach Ihrem Geschmack
Wählen Sie Hell, Dunkel, Sonnenuntergang oder Cyberpunk, oder folgen Sie dem System. In 19 Sprachen verfügbar.

SO GEHT’S

1. Öffnen Sie das Erweiterungsmenü (das Puzzlesymbol) und heften Sie DoneAt an die Symbolleiste.
2. Legen Sie Beginn, Ende und Arbeitstage fest und tippen Sie auf „Countdown starten“.
3. Klicken Sie auf das Symbol, wann immer Sie nachsehen möchten. Mittagspause und Gehalt finden Sie in den Einstellungen.

AUCH AUSSERHALB DES BROWSERS?

DoneAt gibt es auch für Mac und Windows – dort steht die Restzeit in der Menüleiste oder im Infobereich – sowie für iPhone und iPad, mit Widgets für den Home-Bildschirm und Unterstützung für Schichtpläne. Die Schaltfläche „App laden“ in den Einstellungen führt Sie zu doneat.app.

DoneAt ist Open Source: Auf GitHub können Sie genau nachlesen, was es tut.`,
  },

  fr: {
    store: "fr",
    captions: [
      { title: "Sachez quand votre temps vous revient", sub: "Un clic dans la barre d’outils affiche le temps restant, votre progression et ce que vous avez gagné aujourd’hui." },
      { title: "Réglez vos horaires une fois", sub: "Choisissez vos horaires et vos jours travaillés. La pause déjeuner met le décompte en pause, et les nuits qui passent minuit sont bien comptées." },
      { title: "Vos chiffres restent chez vous", sub: "Aucun compte à créer. Horaires, salaire et préférences restent dans ce navigateur, et rien n’est envoyé nulle part." },
      { title: "À votre image", sub: "Thèmes Clair, Sombre, Coucher de soleil et Cyberpunk, en 19 langues. Fonctionne hors ligne." },
    ],
    description: `Sachez exactement quand se termine votre journée, sans garder d’onglet ouvert.

DoneAt place un compte à rebours paisible jusqu’à la fin de la journée dans la barre d’outils de Chrome. Un clic sur l’icône suffit pour voir combien de temps il reste, où vous en êtes et, si vous le souhaitez, ce que vous avez déjà gagné aujourd’hui. Pour tous ceux qui se sont déjà demandé : « Encore combien de temps avant de rentrer ? »

POURQUOI L’INSTALLER

• Un clic depuis n’importe quel onglet
Aucun site à ouvrir, aucune application à changer. Quoi que vous fassiez, la réponse est à un clic, et en fermant la fenêtre vous retrouvez aussitôt votre page.

• Adapté à votre façon de travailler
Réglez une fois vos heures de début et de fin et vos jours travaillés. La pause déjeuner met le décompte en pause, les services de nuit après minuit sont bien comptés, et avant votre journée ou un jour de repos, DoneAt compte jusqu’au prochain service.

• Voir la journée rapporter
Indiquez un salaire mensuel ou journalier et regardez vos gains du jour augmenter seconde après seconde, avec une estimation pour la semaine et pour l’année. Un geste suffit pour masquer le montant si quelqu’un regarde par-dessus votre épaule.

• La confidentialité d’abord
Horaires, salaire et préférences sont enregistrés uniquement dans ce navigateur. Aucun compte, aucune statistique, rien n’est envoyé nulle part. DoneAt ne demande aucune autorisation et ne peut donc pas lire les pages que vous consultez.

• Léger et discret
Rien ne tourne en arrière-plan. DoneAt recalcule tout à partir de l’heure à chaque ouverture : entre deux coups d’œil, il n’utilise ni mémoire ni batterie, et il fonctionne hors ligne.

• À votre image
Choisissez Clair, Sombre, Coucher de soleil ou Cyberpunk, ou suivez le système. Disponible en 19 langues.

POUR COMMENCER

1. Ouvrez le menu des extensions (l’icône en forme de pièce de puzzle) et épinglez DoneAt à la barre d’outils.
2. Réglez vos heures de début et de fin et vos jours travaillés, puis appuyez sur « Démarrer le compte à rebours ».
3. Cliquez sur l’icône dès que vous voulez vérifier. La pause déjeuner et le salaire se règlent dans les Paramètres.

AUSSI EN DEHORS DU NAVIGATEUR ?

DoneAt existe aussi sur Mac et Windows, où le temps restant reste affiché dans la barre des menus ou la zone de notification, ainsi que sur iPhone et iPad, avec des widgets pour l’écran d’accueil et la prise en charge des horaires en rotation. Le bouton « Obtenir l’app » dans les Paramètres vous mène à doneat.app.

DoneAt est open source : vous pouvez vérifier sur GitHub exactement ce qu’il fait.`,
  },

  es: {
    store: "es",
    captions: [
      { title: "Tu hora de salida, siempre a la vista", sub: "Un clic en la barra de herramientas muestra el tiempo que queda, cuánto llevas del día y lo que has ganado hoy." },
      { title: "Tu horario, una sola vez", sub: "Elige tu horario y tus días de trabajo. La pausa para comer detiene el reloj y los turnos de noche que pasan de medianoche se cuentan bien." },
      { title: "Tus datos se quedan contigo", sub: "Sin cuentas. Horario, sueldo y preferencias se guardan en este navegador y no se envían a ningún sitio." },
      { title: "A tu manera", sub: "Temas Claro, Oscuro, Atardecer y Cyberpunk, en 19 idiomas. Funciona sin conexión." },
    ],
    description: `Sabe exactamente cuándo termina tu jornada, sin dejar una pestaña abierta.

DoneAt pone una cuenta atrás tranquila hasta tu hora de salida en la barra de herramientas de Chrome. Haz clic en el icono y verás de un vistazo cuánto queda del día, cuánto llevas y, si quieres, lo que ya has ganado hoy. Está pensado para cualquiera que se haya preguntado alguna vez: "¿cuánto falta para irme a casa?".

POR QUÉ INSTALARLO

• Un clic desde cualquier pestaña
Sin webs que abrir ni aplicaciones que cambiar. Estés haciendo lo que estés haciendo, la respuesta está a un clic, y al cerrar la ventana vuelves directamente a tu página.

• Se adapta a cómo trabajas de verdad
Configura una vez tu hora de entrada y salida y tus días de trabajo. La pausa para comer detiene la cuenta atrás, los turnos de noche que pasan de medianoche se cuentan bien y, antes de tu turno o en un día libre, DoneAt cuenta hasta el siguiente.

• Mira cómo suma tu día
Añade un sueldo mensual o diario y verás cómo crece lo ganado hoy, segundo a segundo, junto con una estimación de esta semana y de este año. Con un toque ocultas la cifra si alguien mira por encima de tu hombro.

• Privado desde el diseño
Tu horario, tu sueldo y tus preferencias se guardan solo en este navegador. Sin cuentas, sin estadísticas y sin enviar nada a ningún sitio. DoneAt no pide ningún permiso, así que no puede leer las páginas que visitas.

• Ligero y silencioso
No se ejecuta nada en segundo plano. DoneAt lo calcula todo a partir de la hora cada vez que lo abres, así que no gasta memoria ni batería entre vistazo y vistazo, y funciona sin conexión.

• A tu manera
Elige Claro, Oscuro, Atardecer o Cyberpunk, o sigue el tema del sistema. Disponible en 19 idiomas.

CÓMO EMPEZAR

1. Abre el menú de extensiones (el icono de la pieza de puzle) y fija DoneAt en la barra de herramientas.
2. Configura tu hora de entrada y salida y tus días de trabajo, y pulsa "Iniciar cuenta regresiva".
3. Haz clic en el icono cuando quieras mirarlo. La pausa para comer y el sueldo están en Ajustes.

¿TAMBIÉN FUERA DEL NAVEGADOR?

DoneAt también está disponible para Mac y Windows, donde el tiempo restante se queda en la barra de menús o en la bandeja del sistema, y para iPhone y iPad, con widgets en la pantalla de inicio y soporte para turnos rotativos. El botón "Descargar la app" de Ajustes te lleva a doneat.app.

DoneAt es de código abierto: puedes comprobar en GitHub exactamente lo que hace.`,
  },

  it: {
    store: "it",
    captions: [
      { title: "Sai quando il tempo torna tuo", sub: "Un clic nella barra degli strumenti mostra il tempo che manca, a che punto sei e quanto hai guadagnato oggi." },
      { title: "Imposta l’orario una volta", sub: "Scegli orari e giorni lavorativi. La pausa pranzo ferma il conteggio e i turni di notte oltre la mezzanotte sono contati correttamente." },
      { title: "I tuoi dati restano tuoi", sub: "Nessun account da creare. Orari, stipendio e preferenze restano in questo browser e non vengono inviati da nessuna parte." },
      { title: "Come piace a te", sub: "Temi Chiaro, Scuro, Tramonto e Cyberpunk, in 19 lingue. Funziona anche offline." },
    ],
    description: `Sai esattamente quando finisce la giornata, senza tenere una scheda aperta.

DoneAt mette un conto alla rovescia tranquillo fino alla fine del lavoro nella barra degli strumenti di Chrome. Fai clic sull’icona e vedi subito quanto manca, a che punto sei e, se vuoi, quanto hai già guadagnato oggi. È pensato per chiunque si sia chiesto almeno una volta: "Quanto manca per tornare a casa?".

PERCHÉ INSTALLARLO

• Un clic da qualsiasi scheda
Nessun sito da aprire, nessuna app da cambiare. Qualunque cosa tu stia facendo, la risposta è a un clic, e chiudendo la finestra torni subito alla tua pagina.

• Si adatta al tuo vero modo di lavorare
Imposta una volta orario di inizio, di fine e giorni lavorativi. La pausa pranzo mette in pausa il conto alla rovescia, i turni di notte oltre la mezzanotte sono contati correttamente e, prima del turno o nei giorni liberi, DoneAt conta fino al turno successivo.

• Guarda la giornata che si somma
Inserisci uno stipendio mensile o giornaliero e guarda crescere secondo dopo secondo quanto hai guadagnato oggi, con una stima per questa settimana e per quest’anno. Con un tocco nascondi l’importo quando qualcuno guarda da sopra la spalla.

• Privacy fin dall’inizio
Orari, stipendio e preferenze sono salvati solo in questo browser. Nessun account, nessuna statistica, niente viene inviato da nessuna parte. DoneAt non chiede alcun permesso, quindi non può leggere le pagine che visiti.

• Leggero e silenzioso
Non gira nulla in background. DoneAt calcola tutto dall’ora attuale ogni volta che lo apri: tra un’occhiata e l’altra non usa memoria né batteria, e funziona anche offline.

• Come piace a te
Scegli Chiaro, Scuro, Tramonto o Cyberpunk, oppure segui il sistema. Disponibile in 19 lingue.

COME INIZIARE

1. Apri il menu delle estensioni (l’icona del puzzle) e fissa DoneAt nella barra degli strumenti.
2. Imposta orario di inizio, di fine e giorni lavorativi, poi premi "Avvia conto alla rovescia".
3. Fai clic sull’icona quando vuoi controllare. Pausa pranzo e stipendio si trovano nelle Impostazioni.

ANCHE FUORI DAL BROWSER?

DoneAt è disponibile anche per Mac e Windows, dove il tempo che manca resta nella barra dei menu o nell’area di notifica, e per iPhone e iPad, con widget per la schermata Home e il supporto ai turni a rotazione. Il pulsante "Scarica l’app" nelle Impostazioni ti porta su doneat.app.

DoneAt è open source: su GitHub puoi verificare esattamente cosa fa.`,
  },

  pt: {
    store: "pt_BR",
    captions: [
      { title: "Saiba quando o tempo volta a ser seu", sub: "Um clique na barra de ferramentas mostra quanto falta, em que ponto do dia você está e quanto já ganhou hoje." },
      { title: "Defina seu horário uma vez", sub: "Escolha seu horário e seus dias de trabalho. O almoço pausa a contagem, e turnos da noite que passam da meia-noite são contados certinho." },
      { title: "Seus dados ficam com você", sub: "Sem cadastro. Horários, salário e preferências ficam neste navegador e não são enviados para lugar nenhum." },
      { title: "Do seu jeito", sub: "Temas Claro, Escuro, Pôr do sol e Cyberpunk, em 19 idiomas. Funciona offline." },
    ],
    description: `Saiba exatamente quando o expediente termina, sem deixar uma aba aberta.

O DoneAt coloca uma contagem regressiva tranquila até o fim do expediente na barra de ferramentas do Chrome. Clique no ícone e veja de relance quanto falta, em que ponto do dia você está e, se quiser, quanto já ganhou hoje. Foi feito para todo mundo que já se perguntou: "Quanto falta para eu ir embora?".

POR QUE INSTALAR

• Um clique em qualquer aba
Nenhum site para abrir, nenhum app para trocar. Não importa o que você esteja fazendo, a resposta está a um clique, e ao fechar a janela você volta direto para a sua página.

• Combina com o seu jeito de trabalhar
Defina uma vez o horário de entrada e saída e os dias de trabalho. O intervalo de almoço pausa a contagem, turnos da noite que passam da meia-noite são contados certinho e, antes do turno ou numa folga, o DoneAt conta até o próximo.

• Veja o dia render
Informe um salário mensal ou diário e acompanhe o quanto você ganhou hoje crescer segundo a segundo, junto com estimativas da semana e do ano. Um toque esconde o valor quando alguém olha por cima do seu ombro.

• Privacidade em primeiro lugar
Horários, salário e preferências ficam salvos só neste navegador. Sem cadastro, sem estatísticas e sem enviar nada para lugar nenhum. O DoneAt não pede nenhuma permissão, então não consegue ler as páginas que você visita.

• Leve e discreto
Nada roda em segundo plano. O DoneAt calcula tudo a partir do relógio sempre que você o abre, então não gasta memória nem bateria entre uma olhada e outra, e funciona offline.

• Do seu jeito
Escolha Claro, Escuro, Pôr do sol ou Cyberpunk, ou siga o sistema. Disponível em 19 idiomas.

COMO COMEÇAR

1. Abra o menu de extensões (o ícone de quebra-cabeça) e fixe o DoneAt na barra de ferramentas.
2. Defina o horário de entrada e saída e os dias de trabalho e toque em "Iniciar contagem regressiva".
3. Clique no ícone sempre que quiser conferir. O almoço e o salário ficam nas configurações.

QUER TAMBÉM FORA DO NAVEGADOR?

O DoneAt também está disponível para Mac e Windows, onde o tempo restante fica na barra de menus ou na bandeja do sistema, e para iPhone e iPad, com widgets na tela de início e suporte a escalas de revezamento. O botão "Obter o app" nas configurações leva você ao doneat.app.

O DoneAt é de código aberto: no GitHub dá para conferir exatamente o que ele faz.`,
  },

  ru: {
    store: "ru",
    captions: [
      { title: "Видно, когда время снова ваше", sub: "Один клик на панели инструментов — и видно, сколько осталось, какая часть дня позади и сколько вы уже заработали." },
      { title: "График задаётся один раз", sub: "Выберите часы и рабочие дни. Обед ставит отсчёт на паузу, а ночные смены после полуночи считаются правильно." },
      { title: "Ваши данные остаются у вас", sub: "Регистрация не нужна. Часы, зарплата и настройки хранятся в этом браузере и никуда не отправляются." },
      { title: "Под ваш вкус", sub: "Темы: светлая, тёмная, «Закат» и «Киберпанк». 19 языков, работает без интернета." },
    ],
    description: `Точно знайте, когда закончится рабочий день, не держа вкладку открытой.

DoneAt добавляет на панель инструментов Chrome спокойный обратный отсчёт до конца рабочего дня. Нажмите на значок — и сразу видно, сколько осталось, какая часть дня уже позади и, если хотите, сколько вы уже заработали сегодня. Для всех, кто хоть раз спрашивал себя: «Сколько ещё до конца работы?»

ПОЧЕМУ СТОИТ УСТАНОВИТЬ

• Один клик из любой вкладки
Не нужно открывать сайт или переключаться в другое приложение. Чем бы вы ни были заняты, ответ в одном клике, а после закрытия окна вы сразу возвращаетесь на свою страницу.

• Подстраивается под ваш реальный график
Время начала и конца и рабочие дни задаются один раз. В обед отсчёт ставится на паузу, ночные смены после полуночи считаются правильно, а до начала смены или в выходной DoneAt считает время до следующей.

• Видно, как складывается день
Укажите месячную или дневную зарплату — и заработок за сегодня будет расти каждую секунду, а рядом появятся оценки за неделю и за год. Одно касание скрывает сумму, если кто-то заглядывает через плечо.

• Приватность прежде всего
Часы, зарплата и настройки хранятся только в этом браузере. Без регистрации, без сбора статистики, ничего никуда не отправляется. DoneAt не запрашивает никаких разрешений, поэтому не может читать страницы, которые вы открываете.

• Лёгкий и незаметный
В фоне ничего не работает. DoneAt пересчитывает всё по текущему времени при каждом открытии, поэтому между проверками не тратит ни память, ни заряд батареи и работает без интернета.

• Под ваш вкус
Выберите светлую, тёмную, «Закат» или «Киберпанк» — или тему системы. Доступен на 19 языках.

КАК НАЧАТЬ

1. Откройте меню расширений (значок пазла) и закрепите DoneAt на панели инструментов.
2. Задайте время начала и конца и рабочие дни, затем нажмите «Начать обратный отсчет».
3. Нажимайте на значок, когда захотите проверить. Обед и зарплата настраиваются в «Настройках».

ХОТИТЕ И ВНЕ БРАУЗЕРА?

DoneAt есть и для Mac и Windows — там оставшееся время всегда видно в строке меню или в трее, — а также для iPhone и iPad, с виджетами на экране «Домой» и поддержкой сменных графиков. Кнопка «Скачать приложение» в настройках ведёт на doneat.app.

У DoneAt открытый исходный код: на GitHub можно проверить, что именно он делает.`,
  },

  "hi-IN": {
    store: "hi",
    captions: [
      { title: "जानिए कब आपका समय आपका होगा", sub: "टूलबार पर एक क्लिक में बचा समय, आज की प्रगति और अब तक की कमाई दिखती है।" },
      { title: "काम के घंटे बस एक बार तय करें", sub: "घंटे और कामकाजी दिन चुनें। दोपहर के अवकाश में गिनती रुक जाती है और आधी रात के बाद तक चलने वाली रात की शिफ़्ट भी सही गिनी जाती है।" },
      { title: "आपका डेटा आपके पास", sub: "खाता बनाने की ज़रूरत नहीं। घंटे, वेतन और पसंद इसी ब्राउज़र में रहते हैं और कहीं नहीं भेजे जाते।" },
      { title: "जैसा आपको पसंद हो", sub: "हल्का, डार्क, सूर्यास्त और साइबरपंक थीम, 19 भाषाओं में। ऑफ़लाइन भी चलता है।" },
    ],
    description: `जानिए काम ठीक कब खत्म होगा, बिना कोई टैब खुला रखे।

DoneAt आपके Chrome टूलबार में छुट्टी तक की एक शांत उलटी गिनती रखता है। आइकन पर क्लिक करें और एक नज़र में देखें कि दिन का कितना समय बचा है, कितना हो चुका है और, अगर आप चाहें, तो आज अब तक कितना कमाया। यह हर उस व्यक्ति के लिए है जिसने कभी सोचा हो, "घर जाने में अभी कितनी देर है?"

इसे क्यों इंस्टॉल करें

• किसी भी टैब से एक क्लिक
न कोई वेबसाइट खोलनी है, न कोई ऐप बदलना है। आप कुछ भी कर रहे हों, जवाब बस एक क्लिक दूर है, और पॉपअप बंद करते ही आप अपने पेज पर लौट आते हैं।

• आपके असली काम के तरीके के हिसाब से
शुरू और खत्म होने का समय और कामकाजी दिन एक बार तय करें। दोपहर के अवकाश में उलटी गिनती रुक जाती है, आधी रात के बाद तक चलने वाली रात की शिफ़्ट सही गिनी जाती है, और शिफ़्ट से पहले या छुट्टी के दिन DoneAt अगली शिफ़्ट तक गिनता है।

• देखिए दिन कैसे जुड़ता है
मासिक या दैनिक वेतन डालें और आज की कमाई को हर सेकंड बढ़ते देखें, साथ में इस हफ़्ते और इस साल का अनुमान भी। कोई पीछे से झाँके तो एक टैप में राशि छुपा दें।

• निजता सबसे पहले
घंटे, वेतन और पसंद सिर्फ़ इसी ब्राउज़र में सेव रहते हैं। न खाता, न आँकड़े इकट्ठा करना, और कुछ भी कहीं नहीं भेजा जाता। DoneAt कोई अनुमति नहीं माँगता, इसलिए यह आपके खोले गए पेज नहीं पढ़ सकता।

• हल्का और शांत
बैकग्राउंड में कुछ नहीं चलता। DoneAt हर बार खोलने पर मौजूदा समय से सब कुछ गिनता है, इसलिए बीच के समय में न मेमोरी लेता है, न बैटरी, और ऑफ़लाइन भी चलता है।

• जैसा आपको पसंद हो
हल्का, डार्क, सूर्यास्त या साइबरपंक चुनें, या सिस्टम के हिसाब से चलने दें। 19 भाषाओं में उपलब्ध।

शुरू कैसे करें

1. एक्सटेंशन मेन्यू (पज़ल आइकन) खोलें और DoneAt को टूलबार पर पिन करें।
2. शुरू और खत्म होने का समय और कामकाजी दिन तय करें, फिर "उलटी गिनती शुरू करें" दबाएँ।
3. जब भी देखना हो, आइकन पर क्लिक करें। दोपहर का अवकाश और वेतन सेटिंग्स में मिलेंगे।

ब्राउज़र के बाहर भी चाहिए?

DoneAt Mac और Windows के लिए भी है, जहाँ बचा समय मेन्यू बार या सिस्टम ट्रे में दिखता रहता है, और iPhone व iPad के लिए भी, होम स्क्रीन विजेट और बदलती शिफ़्टों के सपोर्ट के साथ। सेटिंग्स में "ऐप पाएँ" बटन आपको doneat.app पर ले जाता है।

DoneAt ओपन सोर्स है: यह क्या करता है, यह आप GitHub पर खुद देख सकते हैं।`,
  },

  "mr-IN": {
    store: "mr",
    captions: [
      { title: "तुमचा वेळ कधी तुमचा होतो, ते कळतं", sub: "टूलबारवर एक क्लिक केलं की उरलेला वेळ, आजची प्रगती आणि आतापर्यंतची कमाई दिसते." },
      { title: "कामाचे तास एकदाच ठरवा", sub: "तास आणि कामाचे दिवस निवडा. दुपारच्या सुट्टीत मोजणी थांबते आणि मध्यरात्रीनंतर चालणारी रात्रपाळीही बरोबर मोजली जाते." },
      { title: "तुमचा डेटा तुमच्याकडेच", sub: "खातं उघडायची गरज नाही. तास, पगार आणि पसंती याच ब्राउझरमध्ये राहतात आणि कुठेही पाठवल्या जात नाहीत." },
      { title: "तुम्हाला आवडेल तसं", sub: "लाइट, डार्क, सूर्यास्त आणि सायबरपंक थीम, 19 भाषांमध्ये. ऑफलाइनही चालतं." },
    ],
    description: `काम नेमकं कधी संपणार हे जाणून घ्या, कोणताही टॅब उघडा न ठेवता.

DoneAt तुमच्या Chrome टूलबारमध्ये काम संपेपर्यंतची शांत उलटी मोजणी ठेवतं. आयकॉनवर क्लिक करा आणि एका नजरेत पाहा की दिवसाचा किती वेळ उरला आहे, किती झाला आहे आणि हवं असल्यास आज आतापर्यंत किती कमावलं. "घरी जायला अजून किती वेळ आहे?" असा विचार कधीतरी केलेल्या प्रत्येकासाठी.

हे का इन्स्टॉल करावं

• कोणत्याही टॅबमधून एक क्लिक
वेबसाइट उघडायची गरज नाही, ॲप बदलायची गरज नाही. तुम्ही काहीही करत असा, उत्तर फक्त एका क्लिकवर आहे आणि पॉपअप बंद केलं की तुम्ही लगेच तुमच्या पेजवर परत येता.

• तुमच्या खऱ्या कामाच्या पद्धतीनुसार
सुरुवात आणि शेवटची वेळ आणि कामाचे दिवस एकदाच ठरवा. दुपारच्या सुट्टीत उलटी मोजणी थांबते, मध्यरात्रीनंतर चालणारी रात्रपाळी बरोबर मोजली जाते आणि पाळीच्या आधी किंवा सुट्टीच्या दिवशी DoneAt पुढच्या पाळीपर्यंत मोजतं.

• दिवस कसा भरत जातो ते पाहा
मासिक किंवा दैनिक पगार टाका आणि आजची कमाई दर सेकंदाला वाढताना पाहा, सोबत या आठवड्याचा आणि या वर्षाचा अंदाजही. कुणी मागून डोकावलं तर एका टॅपने रक्कम लपवा.

• गोपनीयता सर्वात आधी
तास, पगार आणि पसंती फक्त याच ब्राउझरमध्ये साठवल्या जातात. खातं नाही, आकडेवारी गोळा करणं नाही आणि काहीही कुठेही पाठवलं जात नाही. DoneAt कोणतीही परवानगी मागत नाही, त्यामुळे तुम्ही उघडलेली पेजेस ते वाचू शकत नाही.

• हलकं आणि शांत
बॅकग्राउंडमध्ये काहीही चालत नाही. DoneAt प्रत्येक वेळी उघडल्यावर सध्याच्या वेळेवरून सगळं मोजतं, त्यामुळे मधल्या वेळेत मेमरी किंवा बॅटरी वापरत नाही आणि ऑफलाइनही चालतं.

• तुम्हाला आवडेल तसं
लाइट, डार्क, सूर्यास्त किंवा सायबरपंक निवडा, किंवा सिस्टमनुसार चालू द्या. 19 भाषांमध्ये उपलब्ध.

सुरुवात कशी करायची

1. एक्स्टेंशन मेन्यू (पझल आयकॉन) उघडा आणि DoneAt टूलबारवर पिन करा.
2. सुरुवात आणि शेवटची वेळ आणि कामाचे दिवस ठरवा, मग "उलट मोजणी सुरू करा" दाबा.
3. पाहायचं असेल तेव्हा आयकॉनवर क्लिक करा. दुपारची सुट्टी आणि पगार सेटिंग्जमध्ये आहेत.

ब्राउझरबाहेरही हवं आहे?

DoneAt Mac आणि Windows साठीही आहे, जिथे उरलेला वेळ मेन्यू बार किंवा सिस्टम ट्रेमध्ये सतत दिसतो, आणि iPhone व iPad साठीही, होम स्क्रीन विजेट आणि बदलत्या पाळ्यांच्या सपोर्टसह. सेटिंग्जमधील "अॅप मिळवा" बटण तुम्हाला doneat.app वर घेऊन जातं.

DoneAt ओपन सोर्स आहे: ते नेमकं काय करतं हे तुम्ही GitHub वर स्वतः पाहू शकता.`,
  },

  tr: {
    store: "tr",
    captions: [
      { title: "Zamanın ne zaman size kalacağını bilin", sub: "Araç çubuğunda tek tık; kalan süreyi, günün ne kadarının geçtiğini ve bugün ne kadar kazandığınızı gösterir." },
      { title: "Mesai saatinizi bir kez ayarlayın", sub: "Saatlerinizi ve çalışma günlerinizi seçin. Öğle molası sayacı durdurur, gece yarısını geçen gece vardiyaları da doğru sayılır." },
      { title: "Verileriniz sizde kalır", sub: "Hesap açmanız gerekmez. Saatler, maaş ve tercihler bu tarayıcıda kalır, hiçbir yere gönderilmez." },
      { title: "Tam istediğiniz gibi", sub: "Açık, Koyu, Gün batımı ve Siberpunk temaları, 19 dilde. Çevrimdışı da çalışır." },
    ],
    description: `Mesainin tam olarak ne zaman biteceğini, bir sekmeyi açık tutmadan bilin.

DoneAt, Chrome araç çubuğunuza paydosa kadar sakin bir geri sayım ekler. Simgeye tıklayın; günün ne kadarının kaldığını, ne kadarını tamamladığınızı ve isterseniz bugün şimdiye kadar ne kadar kazandığınızı tek bakışta görün. "Eve gitmeme daha ne kadar var?" diye düşünmüş herkes için.

NEDEN YÜKLEMELİSİNİZ

• Her sekmeden tek tık
Açılacak bir site, geçilecek bir uygulama yok. Ne yapıyor olursanız olun, cevap bir tık uzağınızda; pencereyi kapatınca doğrudan sayfanıza dönersiniz.

• Gerçek çalışma düzeninize uyar
Başlangıç ve bitiş saatlerinizi ve çalışma günlerinizi bir kez ayarlayın. Öğle molasında geri sayım durur, gece yarısını geçen gece vardiyaları doğru sayılır; vardiyanızdan önce ya da izin gününüzde DoneAt bir sonraki vardiyaya kadar sayar.

• Günün nasıl biriktiğini görün
Aylık ya da günlük maaşınızı girin; bugünkü kazancınızın saniye saniye arttığını, yanında da bu hafta ve bu yıl için tahminleri görün. Biri omzunuzun üzerinden bakarsa tek dokunuşla tutarı gizleyin.

• Önce gizlilik
Saatleriniz, maaşınız ve tercihleriniz yalnızca bu tarayıcıda saklanır. Hesap yok, istatistik toplama yok, hiçbir şey hiçbir yere gönderilmez. DoneAt hiçbir izin istemez; bu yüzden ziyaret ettiğiniz sayfaları okuyamaz.

• Hafif ve sessiz
Arka planda hiçbir şey çalışmaz. DoneAt her açtığınızda her şeyi o anki saate göre hesaplar; aradaki sürede ne bellek ne pil kullanır ve çevrimdışı da çalışır.

• Tam istediğiniz gibi
Açık, Koyu, Gün batımı ya da Siberpunk'ı seçin veya sisteme uyun. 19 dilde kullanılabilir.

NASIL BAŞLANIR

1. Uzantılar menüsünü (yapboz simgesi) açın ve DoneAt'i araç çubuğuna sabitleyin.
2. Başlangıç ve bitiş saatlerinizi ve çalışma günlerinizi ayarlayın, ardından "Geri Sayımı Başlat"a dokunun.
3. Bakmak istediğinizde simgeye tıklayın. Öğle molası ve maaş Ayarlar'da.

TARAYICININ DIŞINDA DA Mİ?

DoneAt, kalan sürenin menü çubuğunda ya da sistem tepsisinde durduğu Mac ve Windows sürümleriyle, ana ekran widget'ları ve dönüşümlü vardiya desteğiyle iPhone ve iPad'de de var. Ayarlar'daki "Uygulamayı al" düğmesi sizi doneat.app'e götürür.

DoneAt açık kaynaklıdır: tam olarak ne yaptığını GitHub'da kontrol edebilirsiniz.`,
  },

  ar: {
    store: "ar",
    captions: [
      { title: "اعرف متى يعود وقتك إليك", sub: "نقرة واحدة في شريط الأدوات تعرض الوقت المتبقي، وكم مضى من يومك، وكم كسبت اليوم." },
      { title: "اضبط ساعات عملك مرة واحدة", sub: "اختر ساعاتك وأيام عملك. استراحة الغداء توقف العدّاد، والورديات الليلية التي تتجاوز منتصف الليل تُحسب بدقة." },
      { title: "بياناتك تبقى معك", sub: "لا حاجة إلى حساب. الساعات والراتب والتفضيلات تبقى في هذا المتصفح، ولا يُرسل أي شيء إلى أي مكان." },
      { title: "كما تحب", sub: "سمات فاتح وداكن وغروب الشمس وسايبربانك، بـ 19 لغة. يعمل دون اتصال." },
    ],
    description: `اعرف بالضبط متى ينتهي دوامك، دون أن تُبقي أي تبويب مفتوحًا.

يضع DoneAt عدًّا تنازليًا هادئًا حتى نهاية الدوام في شريط أدوات Chrome. انقر على الأيقونة لترى بنظرة واحدة كم تبقّى من اليوم، وكم أنجزت منه، وإن أردت، كم كسبت حتى الآن. إنه لكل من سأل نفسه يومًا: "كم بقي حتى أعود إلى البيت؟"

لماذا تثبّته

• نقرة واحدة من أي تبويب
لا موقع تفتحه ولا تطبيق تنتقل إليه. مهما كنت تفعل، الجواب على بُعد نقرة، وعند إغلاق النافذة تعود مباشرة إلى صفحتك.

• يناسب طريقة عملك الحقيقية
اضبط وقت البداية والنهاية وأيام العمل مرة واحدة. يتوقف العدّ التنازلي أثناء استراحة الغداء، وتُحسب الورديات الليلية التي تتجاوز منتصف الليل بدقة، وقبل ورديتك أو في يوم عطلتك يعدّ DoneAt حتى الوردية التالية.

• شاهد يومك وهو يتراكم
أدخل راتبًا شهريًا أو يوميًا وشاهد ما كسبته اليوم يزداد ثانية بعد ثانية، مع تقديرات لهذا الأسبوع وهذا العام. بلمسة واحدة تُخفي المبلغ إذا نظر أحد من فوق كتفك.

• الخصوصية أولًا
تُحفظ ساعاتك وراتبك وتفضيلاتك في هذا المتصفح فقط. لا حساب، ولا جمع إحصاءات، ولا يُرسل أي شيء إلى أي مكان. لا يطلب DoneAt أي أذونات، لذلك لا يستطيع قراءة الصفحات التي تزورها.

• خفيف وهادئ
لا يعمل أي شيء في الخلفية. يحسب DoneAt كل شيء من الوقت الحالي في كل مرة تفتحه، فلا يستهلك ذاكرة ولا بطارية بين النظرة والأخرى، ويعمل دون اتصال.

• كما تحب
اختر فاتح أو داكن أو غروب الشمس أو سايبربانك، أو اتبع إعدادات النظام. متوفر بـ 19 لغة.

كيف تبدأ

1. افتح قائمة الإضافات (أيقونة قطعة الأحجية) وثبّت DoneAt في شريط الأدوات.
2. اضبط وقت البداية والنهاية وأيام العمل، ثم اضغط "ابدأ العد التنازلي".
3. انقر على الأيقونة كلما أردت أن تطمئن. استراحة الغداء والراتب في الإعدادات.

تريده خارج المتصفح أيضًا؟

يتوفر DoneAt أيضًا على Mac وWindows، حيث يبقى الوقت المتبقي في شريط القوائم أو علبة النظام، وعلى iPhone وiPad مع أدوات للشاشة الرئيسية ودعم الورديات المتناوبة. يأخذك زر "نزّل التطبيق" في الإعدادات إلى doneat.app.

DoneAt مفتوح المصدر، فيمكنك أن تتحقق على GitHub مما يفعله بالضبط.`,
  },

  th: {
    store: "th",
    captions: [
      { title: "รู้ว่าเมื่อไหร่เวลาจะเป็นของคุณ", sub: "คลิกเดียวที่แถบเครื่องมือ ก็เห็นเวลาที่เหลือ ความคืบหน้าของวัน และรายได้วันนี้" },
      { title: "ตั้งเวลาทำงานครั้งเดียว", sub: "เลือกเวลาและวันทำงาน พักกลางวันจะหยุดนับชั่วคราว และกะดึกที่เลยเที่ยงคืนก็นับได้ถูกต้อง" },
      { title: "ข้อมูลของคุณอยู่กับคุณ", sub: "ไม่ต้องสมัครบัญชี เวลาทำงาน เงินเดือน และการตั้งค่าอยู่ในเบราว์เซอร์นี้ และไม่ถูกส่งไปที่ไหน" },
      { title: "เป็นแบบที่คุณชอบ", sub: "ธีมสว่าง มืด พระอาทิตย์ตก และไซเบอร์พังก์ ใน 19 ภาษา ใช้ออฟไลน์ได้" },
    ],
    description: `รู้ว่างานจะเลิกตอนไหน โดยไม่ต้องเปิดแท็บค้างไว้

DoneAt วางตัวนับถอยหลังถึงเวลาเลิกงานไว้บนแถบเครื่องมือของ Chrome คลิกที่ไอคอนแล้วคุณจะเห็นได้ทันทีว่าวันนี้เหลือเวลาอีกเท่าไร ผ่านไปแล้วแค่ไหน และถ้าต้องการ ก็ดูได้ว่าวันนี้หาเงินได้เท่าไรแล้ว เหมาะกับทุกคนที่เคยถามตัวเองว่า "อีกนานแค่ไหนถึงจะได้กลับบ้าน"

ทำไมควรติดตั้ง

• คลิกเดียวจากทุกแท็บ
ไม่ต้องเปิดเว็บไซต์ ไม่ต้องสลับแอป ไม่ว่ากำลังทำอะไรอยู่ คำตอบอยู่ห่างแค่คลิกเดียว และเมื่อปิดป๊อปอัปก็กลับไปที่หน้าเดิมได้ทันที

• เข้ากับวิธีทำงานจริงของคุณ
ตั้งเวลาเข้างาน เวลาเลิกงาน และวันทำงานเพียงครั้งเดียว ระหว่างพักกลางวันการนับถอยหลังจะหยุดชั่วคราว กะดึกที่เลยเที่ยงคืนก็นับได้ถูกต้อง และก่อนเข้ากะหรือในวันหยุด DoneAt จะนับถอยหลังไปถึงกะถัดไป

• ดูวันของคุณค่อยๆ เพิ่มขึ้น
ใส่เงินเดือนหรือค่าแรงรายวัน แล้วดูรายได้วันนี้เพิ่มขึ้นทุกวินาที พร้อมประมาณการของสัปดาห์นี้และปีนี้ ถ้ามีใครมองข้ามไหล่ แตะครั้งเดียวก็ซ่อนจำนวนเงินได้

• ความเป็นส่วนตัวมาก่อน
เวลาทำงาน เงินเดือน และการตั้งค่าเก็บไว้ในเบราว์เซอร์นี้เท่านั้น ไม่ต้องสมัครบัญชี ไม่มีการเก็บสถิติ และไม่มีการส่งข้อมูลไปที่ไหน DoneAt ไม่ขอสิทธิ์ใดๆ จึงอ่านหน้าเว็บที่คุณเปิดไม่ได้

• เบาและเงียบ
ไม่มีอะไรทำงานเบื้องหลัง DoneAt คำนวณทุกอย่างจากเวลาปัจจุบันทุกครั้งที่เปิด จึงไม่กินหน่วยความจำหรือแบตเตอรี่ระหว่างที่ไม่ได้ดู และใช้ออฟไลน์ได้

• เป็นแบบที่คุณชอบ
เลือกได้ทั้งสว่าง มืด พระอาทิตย์ตก หรือไซเบอร์พังก์ หรือให้ตามระบบ รองรับ 19 ภาษา

เริ่มต้นใช้งาน

1. เปิดเมนูส่วนขยาย (ไอคอนจิ๊กซอว์) แล้วปักหมุด DoneAt ไว้บนแถบเครื่องมือ
2. ตั้งเวลาเข้างาน เวลาเลิกงาน และวันทำงาน แล้วกด "เริ่มนับถอยหลัง"
3. คลิกไอคอนเมื่อไหร่ก็ได้ที่อยากดู พักกลางวันและเงินเดือนตั้งได้ในการตั้งค่า

อยากเห็นนอกเบราว์เซอร์ด้วยไหม

DoneAt มีให้ใช้บน Mac และ Windows ซึ่งเวลาที่เหลือจะอยู่บนแถบเมนูหรือถาดระบบตลอด และบน iPhone และ iPad พร้อมวิดเจ็ตบนหน้าจอโฮมและรองรับการทำงานเป็นกะ ปุ่ม "รับแอป" ในการตั้งค่าจะพาคุณไปที่ doneat.app

DoneAt เป็นโอเพนซอร์ส คุณตรวจสอบได้บน GitHub ว่ามันทำอะไรบ้าง`,
  },

  id: {
    store: "id",
    captions: [
      { title: "Tahu kapan jam kerja usai", sub: "Sekali klik di toolbar menampilkan sisa waktu, seberapa jauh hari Anda berjalan, dan penghasilan Anda hari ini." },
      { title: "Atur jam kerja sekali saja", sub: "Pilih jam dan hari kerja Anda. Istirahat makan siang menjeda hitungan, dan sif malam yang melewati tengah malam dihitung dengan benar." },
      { title: "Data Anda tetap milik Anda", sub: "Tanpa perlu membuat akun. Jam, gaji, dan preferensi tersimpan di browser ini dan tidak dikirim ke mana pun." },
      { title: "Sesuai selera Anda", sub: "Tema Terang, Gelap, Senja, dan Cyberpunk, dalam 19 bahasa. Bisa dipakai offline." },
    ],
    description: `Ketahui persis kapan hari kerja Anda selesai, tanpa membiarkan tab tetap terbuka.

DoneAt menempatkan hitung mundur yang tenang menuju jam pulang di toolbar Chrome Anda. Klik ikonnya dan lihat sekilas berapa lama lagi hari ini, sudah sejauh mana Anda, dan, jika mau, berapa yang sudah Anda hasilkan hari ini. Dibuat untuk siapa saja yang pernah bertanya, "Berapa lama lagi sampai saya bisa pulang?"

MENGAPA MENGINSTALNYA

• Sekali klik dari tab mana pun
Tidak perlu membuka situs atau berpindah aplikasi. Apa pun yang sedang Anda kerjakan, jawabannya hanya sekali klik, dan saat popup ditutup Anda langsung kembali ke halaman Anda.

• Sesuai cara kerja Anda yang sebenarnya
Atur jam mulai, jam selesai, dan hari kerja sekali saja. Istirahat makan siang menjeda hitung mundur, sif malam yang melewati tengah malam dihitung dengan benar, dan sebelum sif atau pada hari libur DoneAt menghitung mundur ke sif berikutnya.

• Lihat hari Anda bertambah
Masukkan gaji bulanan atau harian dan lihat penghasilan hari ini bertambah detik demi detik, beserta perkiraan untuk minggu ini dan tahun ini. Sekali ketuk menyembunyikan jumlahnya saat ada yang melirik dari belakang.

• Privasi sejak awal
Jam, gaji, dan preferensi Anda hanya disimpan di browser ini. Tanpa akun, tanpa statistik, dan tidak ada yang dikirim ke mana pun. DoneAt tidak meminta izin apa pun, jadi tidak dapat membaca halaman yang Anda kunjungi.

• Ringan dan tenang
Tidak ada yang berjalan di latar belakang. DoneAt menghitung semuanya dari jam saat ini setiap kali dibuka, jadi tidak memakai memori atau baterai di antara pengecekan, dan bisa dipakai offline.

• Sesuai selera Anda
Pilih Terang, Gelap, Senja, atau Cyberpunk, atau ikuti sistem. Tersedia dalam 19 bahasa.

CARA MEMULAI

1. Buka menu ekstensi (ikon puzzle) dan sematkan DoneAt ke toolbar.
2. Atur jam mulai, jam selesai, dan hari kerja, lalu tekan "Mulai Hitung Mundur".
3. Klik ikonnya kapan pun Anda ingin melihat. Istirahat makan siang dan gaji ada di Pengaturan.

INGIN JUGA DI LUAR BROWSER?

DoneAt juga tersedia untuk Mac dan Windows, dengan sisa waktu yang selalu tampil di bilah menu atau baki sistem, serta untuk iPhone dan iPad, dengan widget layar utama dan dukungan sif bergilir. Tombol "Dapatkan aplikasi" di Pengaturan membawa Anda ke doneat.app.

DoneAt bersifat open source: Anda bisa memeriksa di GitHub apa saja yang dilakukannya.`,
  },

  vi: {
    store: "vi",
    captions: [
      { title: "Biết khi nào thời gian là của bạn", sub: "Một cú nhấp trên thanh công cụ cho thấy thời gian còn lại, tiến độ trong ngày và số tiền bạn đã kiếm được hôm nay." },
      { title: "Đặt giờ làm một lần", sub: "Chọn giờ và ngày làm việc. Giờ nghỉ trưa tạm dừng đếm, còn ca đêm kéo qua nửa đêm vẫn được tính đúng." },
      { title: "Dữ liệu của bạn ở lại với bạn", sub: "Không cần tạo tài khoản. Giờ làm, lương và tuỳ chọn nằm trong trình duyệt này và không được gửi đi đâu cả." },
      { title: "Theo cách bạn thích", sub: "Giao diện Sáng, Tối, Hoàng hôn và Cyberpunk, 19 ngôn ngữ. Dùng được khi ngoại tuyến." },
    ],
    description: `Biết chính xác khi nào tan ca, mà không cần mở sẵn một thẻ nào.

DoneAt đặt một bộ đếm ngược nhẹ nhàng đến giờ tan ca ngay trên thanh công cụ Chrome. Nhấp vào biểu tượng là bạn thấy ngay hôm nay còn bao lâu, đã đi được bao xa và, nếu muốn, đã kiếm được bao nhiêu. Dành cho bất kỳ ai từng tự hỏi: "Còn bao lâu nữa mới được về?"

VÌ SAO NÊN CÀI

• Một cú nhấp từ bất kỳ thẻ nào
Không cần mở trang web, không cần chuyển ứng dụng. Dù đang làm gì, câu trả lời chỉ cách một cú nhấp, và khi đóng cửa sổ bạn quay lại ngay trang đang xem.

• Hợp với cách bạn thật sự làm việc
Đặt giờ bắt đầu, giờ kết thúc và ngày làm việc một lần. Giờ nghỉ trưa tạm dừng đếm ngược, ca đêm kéo qua nửa đêm vẫn được tính đúng, và trước ca hay vào ngày nghỉ, DoneAt đếm ngược đến ca tiếp theo.

• Nhìn ngày làm việc cộng dồn
Nhập lương tháng hoặc lương ngày để thấy số tiền hôm nay tăng lên từng giây, kèm ước tính cho tuần này và năm nay. Chỉ một chạm là ẩn số tiền khi có ai nhìn qua vai bạn.

• Quyền riêng tư trên hết
Giờ làm, lương và tuỳ chọn chỉ được lưu trong trình duyệt này. Không tài khoản, không thu thập thống kê, không gửi gì đi đâu cả. DoneAt không yêu cầu bất kỳ quyền nào, nên không thể đọc các trang bạn truy cập.

• Nhẹ nhàng và yên lặng
Không có gì chạy ngầm. DoneAt tính mọi thứ từ giờ hiện tại mỗi khi bạn mở, nên giữa các lần xem không tốn bộ nhớ hay pin, và vẫn chạy khi ngoại tuyến.

• Theo cách bạn thích
Chọn Sáng, Tối, Hoàng hôn hoặc Cyberpunk, hoặc theo hệ thống. Có sẵn 19 ngôn ngữ.

BẮT ĐẦU

1. Mở menu tiện ích (biểu tượng mảnh ghép) và ghim DoneAt lên thanh công cụ.
2. Đặt giờ bắt đầu, giờ kết thúc và ngày làm việc, rồi nhấn "Bắt đầu đếm ngược".
3. Nhấp vào biểu tượng bất cứ khi nào muốn xem. Nghỉ trưa và lương nằm trong Cài đặt.

MUỐN XEM CẢ NGOÀI TRÌNH DUYỆT?

DoneAt cũng có trên Mac và Windows, nơi thời gian còn lại luôn nằm trên thanh menu hoặc khay hệ thống, và trên iPhone, iPad với tiện ích màn hình chính và hỗ trợ ca xoay. Nút "Tải ứng dụng" trong Cài đặt sẽ đưa bạn đến doneat.app.

DoneAt là phần mềm mã nguồn mở: bạn có thể kiểm tra trên GitHub chính xác nó làm gì.`,
  },
};
