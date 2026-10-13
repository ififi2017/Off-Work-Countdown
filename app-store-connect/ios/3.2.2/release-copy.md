# DoneAt 3.2.2 提审文案合集

> 草稿，未改 ASC。包含：美区 iOS 关键词 + 全部 20 语「新功能」。

## 美区（en-US）iOS 关键词

### 3. 主推方案（98/100 字符，98 字节）

```text
calendar,planner,tracker,clock,out,workday,worker,nurse,overtime,wage,hours,widget,leave,alarm,pay
```

- 删：night、rotation。理由：rotation 与副标题 Rota 意思重叠、组合词意图是企业排班；night 单独价值低（night shift 用户多会搜 shift calendar）。
- 加：worker（组成 shift worker，前 3 有 Shift Worker 等排班类，意图对口）、nurse（护士是最大轮班人群，nurse shift 结果全是排班/护理类）、pay（配副标题 Earnings、wage，组成 shift pay / work pay 类长尾）。
- 保留 clock、out（组成 clock out，配名称的 countdown/timer）、alarm、leave（3.2.1 新功能）。
- 规则检查：无空格、无复数、无冠词、无竞品品牌、无 off work，不与名称/副标题重复。新增词的效果未实测（需上线后再测），这里只是选词判断。

### 4. 备选方案（98/100 字符，98 字节）

```text
calendar,planner,tracker,clock,out,workday,worker,nurse,overtime,wage,hours,leave,alarm,pay,roster
```

- 在主推基础上再删 widget、加 roster。理由：widget 几乎不会和 shift 组合搜索（且 Mac 关键词仍保留 widget）；roster 是英/澳常用说法，美区也有部分排班场景用。代价是放弃 widget 相关搜索流量。

### 5. 可选：副标题（会一并重审，名称/副标题是 iOS+Mac 共用字段）

timer 已在名称里，真正能抬「shift timer / shift calendar」的是名称+副标题，而不是关键词字段。可选建议：

```text
Work Shift Calendar & Earnings
```
（30/30）把 Rota 换成 Shift + Calendar：副标题里出现 Shift Calendar 精确短语。若采用，关键词里的 calendar 就重复了，应删掉 calendar（腾出 9 字符，可补回 rotation 或 night）。风险：失去 rota（英区用语，美区影响小）；Mac 页面也会显示。是否采用由老板定，效果需上线后实测。

## 新功能 · zh-Hans / en-US

### zh-Hans（249/4000 字符）

```text
这次更新主要是记录页和请假页改版。
• 记录页重做：周 / 月 / 年 / 人生同一套符号，实心表示已发生、空心表示计划或估算；加班和今天用橙色，节日与补班各有标记。摘要先给结论，再拆工时与预估收入。
• 请假页重做：首页看余额与将过期的假；规划时大号步进选目标天数；方案按用假从少到多排序，带日期条和可用日期列表。
• 补班标签修好了：月历格子里只显示短标签「补班」（英文 Work），点开日期仍是完整的「补班日」；免费用户的锁从日期右上角挪到日期正下方，不再和节日名叠在一起。
• 另外修了一些问题。
```

### en（850/4000 字符）

```text
This update is mostly a redesign of Records and Time off.
• Records rebuilt: Week / Month / Year / Life share one symbol set. Solid means it happened; outline means planned or estimated. Overtime and today are orange; holidays and make-up workdays have their own marks. Summaries lead with a conclusion, then break down hours and estimated pay.
• Time off rebuilt: the home screen shows balances and what expires first; planning uses a large stepper for your goal; plans sort by least leave, with a day strip and an available-dates list.
• Clearer make-up workdays: calendar cells show a short label (Work in English; 补班 in Simplified Chinese), while the full “make-up workday” wording stays in the day detail. For free users, the lock sits centered under the date instead of the top-right corner, so it no longer overlaps holiday names.
• Bug fixes.
```


## 新功能 · 其余 18 语


> 草稿，未改 ASC、未改仓库。源：`asc-3.2.2-whats-new.md`（已批 zh-Hans / en，「方案按用假从少到多排序」）。
> 短标签核对：`src-mobile/ios/App/App/Localizable.xcstrings`（main，#310 之后）`holidayMakeupShort` / `holidayMakeupWorkday`；18 个都已核实。机翻草稿，上架前建议母语者审校。

### zh-Hant（249/4000 字符）

- 短标签 `holidayMakeupShort`：「補班」（已核实）；完整 `holidayMakeupWorkday`：「補班日」

```text
這次更新主要是記錄頁和請假頁改版。
• 記錄頁重做：週 / 月 / 年 / 人生共用同一套符號，實心表示已發生、空心表示計畫或估算；加班和今天用橘色，節日與補班各有標記。摘要先給結論，再拆工時與預估收入。
• 請假頁重做：首頁看餘額與即將過期的假；規劃時用大號步進選目標天數；方案依用假從少到多排序，附日期條和可用日期清單。
• 補班標籤修好了：月曆格子裡只顯示短標籤「補班」，點開日期仍是完整的「補班日」；免費用戶的鎖從日期右上角移到日期正下方，不再和節日名稱疊在一起。
• 另外修正了一些問題。
```

### en-GB（839/4000 字符）

- 短标签 `holidayMakeupShort`：「Work」（已核实）；完整 `holidayMakeupWorkday`：「Make-up workday」

```text
This update is mostly a redesign of Records and Time off.
• Records rebuilt: Week / Month / Year / Life share one symbol set. Solid means it happened; outline means planned or estimated. Overtime and today are orange; holidays and make-up workdays have their own marks. Summaries lead with a conclusion, then break down hours and estimated pay.
• Time off rebuilt: the home screen shows balances and what expires first; planning uses a large stepper for your goal; plans are sorted from least leave used upwards, with a day strip and an available-dates list.
• Clearer make-up workdays: calendar cells show the short label “Work”, while the full “make-up workday” wording stays in the day detail. For free users, the lock now sits centred under the date instead of the top-right corner, so it no longer overlaps holiday names.
• Bug fixes.
```

### ja（377/4000 字符）

- 短标签 `holidayMakeupShort`：「出勤」（已核实）；完整 `holidayMakeupWorkday`：「振替出勤日」

```text
今回のアップデートは、記録画面と休暇画面のリニューアルが中心です。
• 記録画面を刷新：週 / 月 / 年 / 人生で同じ記号を使います。塗りつぶしは実績、白抜きは予定・推定です。残業と今日はオレンジ、祝日と振替出勤日にはそれぞれ印が付きます。サマリーはまず結論を示し、その後に勤務時間と推定収入の内訳を表示します。
• 休暇画面を刷新：ホームで残日数と期限が近い休暇を確認できます。プラン作成では大きなステッパーで目標日数を選べます。プランは使う休暇が少ない順に並び、日付バーと利用可能日リストも表示されます。
• 振替出勤の表示を改善：カレンダーのマスには短いラベル「出勤」だけを表示し、日付を開くと「振替出勤日」と表示されます。無料ユーザーの鍵アイコンは日付の右上から真下に移動し、祝日名と重ならなくなりました。
• その他の不具合を修正しました。
```

### ko（461/4000 字符）

- 短标签 `holidayMakeupShort`：「근무」（已核实）；完整 `holidayMakeupWorkday`：「대체 근무일」

```text
이번 업데이트는 기록 화면과 휴가 화면 개편이 중심입니다.
• 기록 화면 개편: 주 / 월 / 연 / 인생이 같은 기호를 씁니다. 채워진 표시는 이미 지난 일, 빈 표시는 계획 또는 추정입니다. 초과 근무와 오늘은 주황색이며, 공휴일과 대체 근무일에는 각각 표시가 붙습니다. 요약은 결론을 먼저 보여 주고 근무 시간과 예상 수입을 나눠 보여 줍니다.
• 휴가 화면 개편: 홈에서 잔여 휴가와 곧 만료되는 휴가를 확인할 수 있습니다. 계획할 때 큰 스테퍼로 목표 일수를 고릅니다. 플랜은 사용하는 휴가가 적은 순으로 정렬되며 날짜 바와 사용 가능 날짜 목록이 함께 나옵니다.
• 대체 근무 표시 개선: 달력 칸에는 짧은 라벨 「근무」만 표시하고, 날짜를 열면 전체 이름 「대체 근무일」이 보입니다. 무료 사용자의 자물쇠는 날짜 오른쪽 위에서 날짜 바로 아래로 옮겨 공휴일 이름과 겹치지 않습니다.
• 기타 버그를 수정했습니다.
```

### de-DE（926/4000 字符）

- 短标签 `holidayMakeupShort`：「Arbeit」（已核实）；完整 `holidayMakeupWorkday`：「Ersatzarbeitstag」

```text
Dieses Update bringt vor allem neu gestaltete Bereiche „Aufzeichnungen“ und „Urlaub“.
• Aufzeichnungen neu: Woche / Monat / Jahr / Leben nutzen dieselben Symbole. Gefüllt heißt erledigt, umrandet heißt geplant oder geschätzt. Überstunden und heute sind orange; Feiertage und Ersatzarbeitstage haben eigene Markierungen. Zusammenfassungen nennen zuerst das Fazit, dann Stunden und geschätztes Einkommen.
• Urlaub neu: Die Startseite zeigt Guthaben und was zuerst verfällt; bei der Planung wählst du dein Ziel mit einem großen Stepper; Pläne sind nach verbrauchten Urlaubstagen aufsteigend sortiert, mit Tagesleiste und Liste verfügbarer Daten.
• Ersatzarbeitstage klarer: Kalenderzellen zeigen nur das kurze Label „Arbeit“, in den Tagesdetails steht weiterhin „Ersatzarbeitstag“. Für kostenlose Nutzer sitzt das Schloss jetzt mittig unter dem Datum statt oben rechts und überdeckt keine Feiertagsnamen mehr.
• Fehlerbehebungen.
```

### fr-FR（1012/4000 字符）

- 短标签 `holidayMakeupShort`：「Travail」（已核实）；完整 `holidayMakeupWorkday`：「Jour travaillé de rattrapage」

```text
Cette mise à jour repense surtout les écrans Historique et Congés.
• Historique repensé : Semaine / Mois / Année / Vie partagent les mêmes symboles. Plein = c’est passé ; contour = prévu ou estimé. Les heures sup et aujourd’hui sont en orange ; jours fériés et jours travaillés de rattrapage ont leur propre marque. Les résumés donnent d’abord la conclusion, puis le détail des heures et du revenu estimé.
• Congés repensés : l’accueil affiche vos soldes et ce qui expire en premier ; la planification utilise un grand sélecteur pour votre objectif ; les plans sont triés du moins au plus de congés utilisés, avec une frise des jours et une liste des dates disponibles.
• Jours de rattrapage plus lisibles : les cases du calendrier affichent seulement le libellé court « Travail », le détail du jour garde « Jour travaillé de rattrapage ». Pour les utilisateurs gratuits, le cadenas est désormais centré sous la date au lieu du coin supérieur droit et ne chevauche plus les noms des fêtes.
• Corrections de bugs.
```

### es-ES（1028/4000 字符）

- 短标签 `holidayMakeupShort`：「Trabajo」（已核实）；完整 `holidayMakeupWorkday`：「Día laborable compensatorio」

```text
Esta actualización renueva sobre todo Registros y Vacaciones.
• Registros renovado: Semana / Mes / Año / Vida usan los mismos símbolos. Relleno significa que ya ocurrió; contorno, que está planificado o estimado. Las horas extra y el día de hoy van en naranja; los festivos y los días laborables compensatorios tienen su propia marca. Los resúmenes empiezan por la conclusión y luego desglosan horas e ingresos estimados.
• Vacaciones renovado: la pantalla principal muestra tu saldo y lo que caduca antes; al planificar eliges tu objetivo con un selector grande; los planes se ordenan de menos a más días usados, con una franja de días y una lista de fechas disponibles.
• Días compensatorios más claros: las celdas del calendario muestran solo la etiqueta corta «Trabajo», y el detalle del día sigue mostrando «Día laborable compensatorio». Para usuarios gratuitos, el candado pasa a estar centrado bajo la fecha en lugar de la esquina superior derecha, así que ya no tapa los nombres de los festivos.
• Corrección de errores.
```

### es-MX（1029/4000 字符）

- 短标签 `holidayMakeupShort`：「Trabajo」（已核实）；完整 `holidayMakeupWorkday`：「Día laborable compensatorio」

```text
Esta actualización renueva sobre todo Registros y Vacaciones.
• Registros renovado: Semana / Mes / Año / Vida usan los mismos símbolos. Relleno significa que ya ocurrió; contorno, que está planificado o estimado. Las horas extra y el día de hoy van en naranja; los festivos y los días laborables compensatorios tienen su propia marca. Los resúmenes empiezan por la conclusión y luego desglosan horas e ingresos estimados.
• Vacaciones renovado: la pantalla principal muestra tu saldo y lo que caduca antes; al planificar eliges tu objetivo con un selector grande; los planes se ordenan de menos a más días usados, con una franja de días y una lista de fechas disponibles.
• Días compensatorios más claros: las celdas del calendario muestran solo la etiqueta corta “Trabajo”, y el detalle del día sigue mostrando “Día laborable compensatorio”. Para usuarios gratuitos, el candado ahora aparece centrado bajo la fecha en lugar de la esquina superior derecha, así que ya no tapa los nombres de los festivos.
• Corrección de errores.
```

### it（982/4000 字符）

- 短标签 `holidayMakeupShort`：「Lavoro」（已核实）；完整 `holidayMakeupWorkday`：「Giorno lavorativo di recupero」

```text
Questo aggiornamento rinnova soprattutto Registro e Ferie.
• Registro rinnovato: Settimana / Mese / Anno / Vita usano gli stessi simboli. Pieno significa già avvenuto; contorno significa pianificato o stimato. Straordinari e oggi sono in arancione; festività e giorni lavorativi di recupero hanno un proprio segno. I riepiloghi partono dalla conclusione, poi dettagliano ore e guadagno stimato.
• Ferie rinnovate: la schermata principale mostra i saldi e cosa scade prima; nella pianificazione scegli l’obiettivo con un grande selettore; i piani sono ordinati da meno a più giorni di ferie usati, con una barra dei giorni e un elenco di date disponibili.
• Giorni di recupero più chiari: le celle del calendario mostrano solo l’etichetta breve «Lavoro», mentre il dettaglio del giorno mantiene «Giorno lavorativo di recupero». Per gli utenti gratuiti, il lucchetto ora è centrato sotto la data invece che in alto a destra e non copre più i nomi delle festività.
• Correzioni di bug.
```

### pt-BR（981/4000 字符）

- 短标签 `holidayMakeupShort`：「Trabalho」（已核实）；完整 `holidayMakeupWorkday`：「Dia de trabalho compensatório」

```text
Esta atualização traz principalmente o redesign de Registros e Folgas.
• Registros refeitos: Semana / Mês / Ano / Vida usam o mesmo conjunto de símbolos. Preenchido significa que já aconteceu; contorno significa planejado ou estimado. Hora extra e hoje ficam em laranja; feriados e dias de trabalho compensatório têm marcas próprias. Os resumos começam pela conclusão e depois detalham horas e ganho estimado.
• Folgas refeitas: a tela inicial mostra saldos e o que vence primeiro; no planejamento você escolhe a meta com um seletor grande; os planos são ordenados do menor para o maior uso de folgas, com uma faixa de dias e uma lista de datas disponíveis.
• Dias compensatórios mais claros: as células do calendário mostram só o rótulo curto “Trabalho”, e o detalhe do dia continua com “Dia de trabalho compensatório”. Para usuários gratuitos, o cadeado agora fica centralizado abaixo da data, e não no canto superior direito, sem sobrepor nomes de feriados.
• Correções de bugs.
```

### ru（927/4000 字符）

- 短标签 `holidayMakeupShort`：「Работа」（已核实）；完整 `holidayMakeupWorkday`：「Перенесённый рабочий день」

```text
В этом обновлении главное — новые экраны «Записи» и «Отпуск».
• «Записи» переработаны: неделя / месяц / год / жизнь используют одни и те же символы. Заполненный — уже было, контурный — запланировано или оценка. Переработки и сегодняшний день — оранжевые; праздники и перенесённые рабочие дни отмечены отдельно. Сводки сначала дают вывод, затем разбивку по часам и ориентировочному доходу.
• «Отпуск» переработан: на главном экране — остатки и то, что сгорит раньше; при планировании цель выбирается крупным переключателем; варианты отсортированы от меньшего расхода отпуска к большему, с лентой дней и списком доступных дат.
• Понятнее перенесённые рабочие дни: в ячейках календаря только короткая метка «Работа», а в карточке дня по‑прежнему «Перенесённый рабочий день». У бесплатных пользователей замок теперь по центру под датой, а не в правом верхнем углу, и больше не перекрывает названия праздников.
• Исправления ошибок.
```

### ar-SA（814/4000 字符）

- 短标签 `holidayMakeupShort`：「عمل」（已核实）；完整 `holidayMakeupWorkday`：「يوم عمل تعويضي」

```text
يركّز هذا التحديث على إعادة تصميم صفحتي السجلات والإجازات.
• إعادة بناء السجلات: الأسبوع / الشهر / السنة / العمر تستخدم مجموعة الرموز نفسها. الرمز المملوء يعني أنه حدث، والمفرّغ يعني أنه مخطط أو تقديري. العمل الإضافي واليوم باللون البرتقالي، وللعطلات وأيام العمل التعويضية علامات خاصة. تبدأ الملخصات بالخلاصة ثم تفصّل الساعات والدخل التقديري.
• إعادة بناء الإجازات: تعرض الشاشة الرئيسية الأرصدة وما ينتهي أولًا، ويُختار الهدف عند التخطيط بعدّاد كبير، وتُرتَّب الخطط من الأقل استخدامًا للإجازة إلى الأكثر، مع شريط أيام وقائمة بالتواريخ المتاحة.
• أيام العمل التعويضية أوضح: تعرض خانات التقويم التسمية القصيرة «عمل» فقط، بينما تبقى عبارة «يوم عمل تعويضي» كاملة في تفاصيل اليوم. وللمستخدمين المجانيين، أصبح القفل في المنتصف أسفل التاريخ بدلًا من الزاوية العلوية اليمنى، فلم يعد يتداخل مع أسماء العطلات.
• إصلاح أخطاء.
```

### hi（863/4000 字符）

- 短标签 `holidayMakeupShort`：「काम」（已核实）；完整 `holidayMakeupWorkday`：「प्रतिपूरक कार्यदिवस」

```text
यह अपडेट मुख्य रूप से रिकॉर्ड और छुट्टी स्क्रीन का नया डिज़ाइन है।
• रिकॉर्ड नए सिरे से: सप्ताह / महीना / साल / जीवन एक ही प्रतीक सेट इस्तेमाल करते हैं। भरा हुआ = हो चुका; खाली रूपरेखा = योजना या अनुमान। ओवरटाइम और आज नारंगी रंग में; छुट्टियों और प्रतिपूरक कार्यदिवसों के अपने निशान हैं। सारांश पहले निष्कर्ष बताता है, फिर घंटे और अनुमानित आय का ब्योरा।
• छुट्टी नए सिरे से: होम स्क्रीन पर बैलेंस और सबसे पहले खत्म होने वाली छुट्टियाँ; योजना में बड़े स्टेपर से लक्ष्य चुनें; प्लान कम से ज़्यादा छुट्टी इस्तेमाल के क्रम में लगते हैं, साथ में दिनों की पट्टी और उपलब्ध तारीखों की सूची।
• प्रतिपूरक कार्यदिवस अब साफ़: कैलेंडर के खानों में सिर्फ़ छोटा लेबल “काम” दिखता है, जबकि दिन के विवरण में पूरा “प्रतिपूरक कार्यदिवस” रहता है। मुफ़्त उपयोगकर्ताओं के लिए ताला अब ऊपर दाएँ कोने की जगह तारीख के ठीक नीचे बीच में है, इसलिए छुट्टियों के नामों पर नहीं चढ़ता।
• बग सुधार।
```

### mr-IN（790/4000 字符）

- 短标签 `holidayMakeupShort`：「काम」（已核实）；完整 `holidayMakeupWorkday`：「बदली कामाचा दिवस」

```text
या अपडेटमध्ये मुख्यतः नोंदी आणि रजा स्क्रीनचे नवे डिझाइन आहे.
• नोंदी नव्याने: आठवडा / महिना / वर्ष / आयुष्य एकच चिन्हसंच वापरतात. भरलेले = घडून गेले; बाह्यरेषा = नियोजित किंवा अंदाजित. ओव्हरटाइम आणि आज नारिंगी रंगात; सुट्ट्या आणि बदली कामाच्या दिवसांना स्वतंत्र खुणा. सारांश आधी निष्कर्ष देतो, मग तास आणि अंदाजित उत्पन्नाचा तपशील.
• रजा नव्याने: होम स्क्रीनवर शिल्लक आणि आधी संपणाऱ्या रजा; नियोजनात मोठ्या स्टेपरने लक्ष्य निवडा; योजना कमी ते जास्त रजा वापरानुसार क्रमाने, दिवसांची पट्टी आणि उपलब्ध तारखांच्या यादीसह.
• बदली कामाचे दिवस अधिक स्पष्ट: कॅलेंडरच्या चौकटीत फक्त लहान लेबल “काम” दिसते, तर दिवसाच्या तपशिलात पूर्ण “बदली कामाचा दिवस” राहते. मोफत वापरकर्त्यांसाठी कुलूप आता वरच्या उजव्या कोपऱ्याऐवजी तारखेखाली मध्यभागी आहे, त्यामुळे सुट्ट्यांच्या नावांवर येत नाही.
• दोष दुरुस्त्या.
```

### tr（885/4000 字符）

- 短标签 `holidayMakeupShort`：「Mesai」（已核实）；完整 `holidayMakeupWorkday`：「Telafi iş günü」

```text
Bu güncelleme ağırlıklı olarak Kayıtlar ve İzin ekranlarını yeniliyor.
• Kayıtlar yenilendi: Hafta / Ay / Yıl / Hayat aynı sembol setini kullanır. Dolu, gerçekleşti; çerçeve, planlanan veya tahmini demektir. Fazla mesai ve bugün turuncu; resmî tatiller ve telafi iş günlerinin kendi işaretleri var. Özetler önce sonucu verir, sonra saatleri ve tahmini kazancı ayrıntılandırır.
• İzin yenilendi: ana ekran bakiyeleri ve ilk bitecek izinleri gösterir; planlamada hedefi büyük bir sayaçla seçersiniz; planlar en az izin kullanandan çoğa doğru sıralanır, gün şeridi ve uygun tarihler listesiyle.
• Telafi iş günleri daha net: takvim hücreleri yalnızca kısa “Mesai” etiketini gösterir, gün ayrıntısında tam “Telafi iş günü” ifadesi kalır. Ücretsiz kullanıcılar için kilit artık sağ üst köşe yerine tarihin altında ortalanmış durumda, böylece tatil adlarıyla çakışmıyor.
• Hata düzeltmeleri.
```

### th（685/4000 字符）

- 短标签 `holidayMakeupShort`：「ทำงาน」（已核实）；完整 `holidayMakeupWorkday`：「วันทำงานชดเชย」

```text
อัปเดตนี้เน้นการออกแบบหน้าบันทึกและหน้าลางานใหม่
• หน้าบันทึกใหม่: สัปดาห์ / เดือน / ปี / ชีวิต ใช้สัญลักษณ์ชุดเดียวกัน แบบทึบคือเกิดขึ้นแล้ว แบบโครงคือแผนหรือค่าประมาณ ทำงานล่วงเวลาและวันนี้เป็นสีส้ม วันหยุดและวันทำงานชดเชยมีเครื่องหมายของตัวเอง สรุปจะบอกผลก่อน แล้วค่อยแยกชั่วโมงและรายได้โดยประมาณ
• หน้าลางานใหม่: หน้าแรกแสดงวันลาคงเหลือและวันลาที่จะหมดอายุก่อน ตอนวางแผนเลือกเป้าหมายด้วยปุ่มปรับขนาดใหญ่ แผนเรียงจากใช้วันลาน้อยไปมาก พร้อมแถบวันและรายการวันที่ว่าง
• วันทำงานชดเชยชัดขึ้น: ช่องปฏิทินแสดงเฉพาะป้ายสั้น “ทำงาน” ส่วนรายละเอียดวันยังแสดง “วันทำงานชดเชย” เต็ม ๆ สำหรับผู้ใช้ฟรี ไอคอนแม่กุญแจย้ายจากมุมขวาบนมาอยู่กึ่งกลางใต้วันที่ จึงไม่ทับชื่อวันหยุดอีก
• แก้ไขข้อบกพร่อง
```

### id（959/4000 字符）

- 短标签 `holidayMakeupShort`：「Kerja」（已核实）；完整 `holidayMakeupWorkday`：「Hari kerja pengganti」

```text
Pembaruan ini terutama mendesain ulang Catatan dan Cuti.
• Catatan dibangun ulang: Minggu / Bulan / Tahun / Hidup memakai set simbol yang sama. Terisi berarti sudah terjadi; garis tepi berarti rencana atau perkiraan. Lembur dan hari ini berwarna oranye; hari libur dan hari kerja pengganti punya tanda sendiri. Ringkasan dimulai dengan kesimpulan, lalu merinci jam dan perkiraan penghasilan.
• Cuti dibangun ulang: layar utama menampilkan saldo dan cuti yang paling dulu kedaluwarsa; saat merencanakan, pilih target dengan stepper besar; rencana diurutkan dari pemakaian cuti paling sedikit ke paling banyak, dengan strip hari dan daftar tanggal tersedia.
• Hari kerja pengganti lebih jelas: sel kalender hanya menampilkan label pendek “Kerja”, sedangkan detail hari tetap memakai “Hari kerja pengganti”. Untuk pengguna gratis, ikon gembok kini di tengah bawah tanggal, bukan di pojok kanan atas, sehingga tidak lagi menutupi nama hari libur.
• Perbaikan bug.
```

### vi（822/4000 字符）

- 短标签 `holidayMakeupShort`：「Làm bù」（已核实）；完整 `holidayMakeupWorkday`：「Ngày làm bù」

```text
Bản cập nhật này chủ yếu thiết kế lại màn hình Nhật ký và Nghỉ phép.
• Nhật ký làm mới: Tuần / Tháng / Năm / Cuộc đời dùng chung một bộ ký hiệu. Tô đặc là đã diễn ra; viền rỗng là kế hoạch hoặc ước tính. Tăng ca và hôm nay có màu cam; ngày lễ và ngày làm bù có dấu riêng. Phần tóm tắt nêu kết luận trước, rồi chia nhỏ giờ làm và thu nhập ước tính.
• Nghỉ phép làm mới: màn hình chính hiện số ngày phép còn lại và phép sắp hết hạn; khi lập kế hoạch, chọn mục tiêu bằng nút tăng giảm cỡ lớn; các phương án xếp từ ít ngày phép đến nhiều, kèm dải ngày và danh sách ngày khả dụng.
• Ngày làm bù rõ hơn: ô lịch chỉ hiện nhãn ngắn “Làm bù”, còn chi tiết ngày vẫn ghi đầy đủ “Ngày làm bù”. Với người dùng miễn phí, biểu tượng khóa nay nằm giữa ngay dưới ngày thay vì góc trên bên phải, nên không còn đè lên tên ngày lễ.
• Sửa lỗi.
```
