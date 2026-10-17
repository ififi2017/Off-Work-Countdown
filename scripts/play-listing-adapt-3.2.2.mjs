#!/usr/bin/env node
// Builds the non-English/Chinese Play 3.2.2 listings from the reviewed ASC
// 3.2.2 metadata (app-store-connect/ios/3.2.2.json). Each ASC description has
// the same eleven blocks; the Apple-only ones are dropped or rewritten for
// Android, as the reviewed English Play copy does:
//   1 Apple Watch, 4 iPhone Duo, 9 "follow us"  → removed
//   3 widgets / Live Activities / Dynamic Island → Android widgets + countdown notification
//   6 Plus list: the iCloud sync bullet          → removed
//   7 subscription terms                          → Google Play terms
//   8 data section                                → Android backup, verification service
//   10 Apple EULA + privacy                       → privacy + support
// en-US and zh-CN keep the reviewed copy in docs/android/store-listing.md.
//
//   node scripts/play-listing-adapt-3.2.2.mjs [--write]   # prints counts; --write updates play-store/3.2.2.json
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const asc = JSON.parse(readFileSync(join(root, 'app-store-connect/ios/3.2.2.json'), 'utf8')).localizations;
const configPath = join(root, 'play-store/3.2.2.json');

const L = {
  ar: { asc: 'ar-SA', title: 'DoneAt - عداد نهاية الدوام', short: 'عدّ تنازلي لنهاية الدوام، وجدول المناوبات والإجازات والسجلات في لمحة واحدة',
    glance: 'أداة الشاشة الرئيسية في Android وإشعار العد التنازلي في لوحة الإشعارات وعلى شاشة القفل. تصميم خاص للوضع الأفقي وللشاشات الكبيرة. شارك العد التنازلي كصورة أو رابط. متوفر بـ19 لغة.',
    subs: 'اشترك شهريًا أو سنويًا، أو احصل على خيار مدى الحياة بشراء واحد. يعرض Google Play السعر المحلي والشروط قبل الشراء. تتجدد الاشتراكات تلقائيًا حتى تلغيها. قد تتضمن الخطة السنوية المؤهلة سبعة أيام مجانية، ثم يُحتسب السعر السنوي المعروض ما لم تُلغِ قبل انتهاء التجربة. أدِر اشتراكاتك في Google Play. شراء خيار مدى الحياة لا يلغي اشتراكًا قائمًا.',
    data: 'لا حساب في DoneAt ولا إعلانات. تبقى السجلات والراتب افتراضيًا على جهازك. قد تشمل نسخة Android الاحتياطية أو نقل البيانات إلى جهاز جديد السجلات والإعدادات، بما فيها الراتب. يمكنك تصدير ملفاتك واستيرادها بنفسك؛ لا توجد مزامنة تلقائية مع Google Drive. يتم التحقق من المشتريات عبر Google Play وخدمة التحقق من DoneAt، ولا تُرسل إليها سجلات العمل أو الراتب. لا يظهر الراتب في الأدوات أو الإشعارات أو الصور والروابط التي تشاركها.',
    support: 'الدعم' },
  'de-DE': { asc: 'de-DE', title: 'DoneAt - Feierabend Countdown', short: 'Countdown bis Feierabend, Schichtplan, Urlaub und Arbeitszeiten auf einen Blick',
    glance: 'Home-Bildschirm-Widgets für Android und eine Countdown-Mitteilung in der Benachrichtigungsleiste und auf dem Sperrbildschirm. Eigene Layouts für Querformat und große Bildschirme. Teile deinen Countdown als Bild oder Link. Verfügbar in 19 Sprachen.',
    subs: 'Abonniere monatlich oder jährlich oder sichere dir lebenslangen Zugriff mit einem Einmalkauf. Google Play zeigt dir vor dem Kauf den lokalen Preis und die Bedingungen. Abos verlängern sich automatisch, bis du kündigst. Ein berechtigtes Jahresabo kann sieben kostenlose Tage enthalten; danach gilt der angezeigte Jahrespreis, wenn du nicht vor Ende des Probezeitraums kündigst. Abos verwaltest du in Google Play. Der Kauf des lebenslangen Zugriffs kündigt ein bestehendes Abo nicht.',
    data: 'Kein DoneAt-Konto, keine Werbung. Einträge und Gehalt bleiben standardmäßig auf deinem Gerät. Die Android-Sicherung oder ein Geräteumzug kann Einträge und Einstellungen samt Gehalt mitnehmen. Du kannst eigene Dateien exportieren und importieren; eine automatische Google Drive-Synchronisierung gibt es nicht. Käufe werden über Google Play und den Prüfdienst von DoneAt bestätigt; Arbeitsdaten und Gehalt werden dorthin nicht gesendet. Widgets, Mitteilungen sowie geteilte Bilder und Links enthalten nie dein Gehalt.',
    support: 'Support' },
  'en-GB': { asc: 'en-GB', title: 'DoneAt: Work Shift Countdown', short: 'Your shift countdown, rota, time off and records at a glance',
    glance: 'Android Home Screen widgets and a countdown notification in the notification shade and on the Lock Screen. Landscape and large screens get their own layouts. Share your countdown as an image or a link. Available in 19 languages.',
    subs: 'Subscribe monthly or yearly, or get Lifetime with a single purchase. Google Play shows the local price and terms before you buy. Subscriptions renew automatically until cancelled. An eligible yearly plan may include seven free days, followed by the displayed yearly price unless you cancel before the trial ends. Manage subscriptions in Google Play. Buying Lifetime does not cancel an existing subscription.',
    data: 'No DoneAt account, no ads. Your records and pay stay on your device by default. Android backup or a device transfer can include records and settings, including pay. You can export and import your own files; there is no automatic Google Drive sync. Purchases are verified with Google Play and DoneAt’s verification service; your work records and pay are never sent to it. Widgets, notifications and shared images or links never show your pay.',
    support: 'Support' },
  'es-ES': { asc: 'es-ES', title: 'DoneAt - Cuenta atrás y turnos', short: 'Cuenta atrás de tu turno, cuadrante, vacaciones y registros de un vistazo',
    glance: 'Widgets de pantalla de inicio en Android y una notificación de cuenta atrás en el panel de notificaciones y la pantalla bloqueada. El modo horizontal y las pantallas grandes tienen su propio diseño. Comparte la cuenta atrás como imagen o enlace. Disponible en 19 idiomas.',
    subs: 'Suscríbete por meses o por años, o hazte con el acceso de por vida en una sola compra. Google Play te muestra el precio local y las condiciones antes de comprar. Las suscripciones se renuevan automáticamente hasta que las canceles. Un plan anual que cumpla los requisitos puede incluir siete días gratis; después se cobra el precio anual indicado, salvo que canceles antes de que termine la prueba. Gestiona tus suscripciones en Google Play. Comprar el acceso de por vida no cancela una suscripción que ya tengas.',
    data: 'Sin cuenta de DoneAt y sin anuncios. Tus registros y tu sueldo se quedan en tu dispositivo por defecto. La copia de seguridad de Android o el traspaso a otro dispositivo pueden incluir registros y ajustes, sueldo incluido. Puedes exportar e importar tus propios archivos; no hay sincronización automática con Google Drive. Las compras se verifican con Google Play y el servicio de verificación de DoneAt, al que nunca se envían tus registros ni tu sueldo. Los widgets, las notificaciones y las imágenes o enlaces que compartes nunca muestran tu sueldo.',
    support: 'Soporte' },
  'es-419': { asc: 'es-MX', title: 'DoneAt - Cuenta regresiva', short: 'Cuenta regresiva de tu turno, rol, vacaciones y registros de un vistazo',
    glance: 'Widgets de pantalla de inicio en Android y una notificación de cuenta regresiva en el panel de notificaciones y la pantalla bloqueada. El modo horizontal y las pantallas grandes tienen su propio diseño. Comparte la cuenta regresiva como imagen o enlace. Disponible en 19 idiomas.',
    subs: 'Suscríbete por mes o por año, o consigue el acceso de por vida con una sola compra. Google Play te muestra el precio local y las condiciones antes de comprar. Las suscripciones se renuevan automáticamente hasta que las canceles. Un plan anual que cumpla los requisitos puede incluir siete días gratis; después se cobra el precio anual indicado, a menos que canceles antes de que termine la prueba. Administra tus suscripciones en Google Play. Comprar el acceso de por vida no cancela una suscripción que ya tengas.',
    data: 'Sin cuenta de DoneAt y sin anuncios. Tus registros y tu sueldo se quedan en tu dispositivo de forma predeterminada. La copia de seguridad de Android o la transferencia a otro dispositivo pueden incluir registros y configuración, sueldo incluido. Puedes exportar e importar tus propios archivos; no hay sincronización automática con Google Drive. Las compras se verifican con Google Play y el servicio de verificación de DoneAt, al que nunca se envían tus registros ni tu sueldo. Los widgets, las notificaciones y las imágenes o enlaces que compartes nunca muestran tu sueldo.',
    support: 'Soporte' },
  'fr-FR': { asc: 'fr-FR', title: 'DoneAt - Travail posté, 3x8', short: "Compte à rebours, planning, congés et historique de vos heures en un coup d'œil",
    glance: "Widgets d'écran d'accueil Android et notification de compte à rebours dans le volet des notifications et sur l'écran verrouillé. Le mode paysage et les grands écrans ont leur propre mise en page. Partagez votre compte à rebours en image ou en lien. En 19 langues.",
    subs: "Abonnez-vous au mois ou à l'année, ou prenez l'accès à vie en un seul achat. Google Play affiche le prix local et les conditions avant l'achat. Les abonnements se renouvellent automatiquement jusqu'à leur résiliation. Une formule annuelle éligible peut inclure sept jours gratuits, puis le prix annuel affiché s'applique, sauf résiliation avant la fin de l'essai. Gérez vos abonnements dans Google Play. L'achat de l'accès à vie ne résilie pas un abonnement en cours.",
    data: "Pas de compte DoneAt, pas de pub. Par défaut, vos relevés et votre salaire restent sur votre appareil. La sauvegarde Android ou le transfert vers un nouvel appareil peuvent inclure relevés et réglages, salaire compris. Vous pouvez exporter et importer vos propres fichiers ; aucune synchronisation automatique avec Google Drive. Les achats sont vérifiés par Google Play et par le service de vérification de DoneAt, qui ne reçoit jamais vos relevés ni votre salaire. Les widgets, les notifications et les images ou liens partagés n'affichent jamais votre salaire.",
    support: 'Assistance' },
  'hi-IN': { asc: 'hi', title: 'DoneAt - शिफ्ट काउंटडाउन टाइमर', short: 'शिफ़्ट काउंटडाउन, ड्यूटी रोस्टर, छुट्टियाँ और रिकॉर्ड, सब एक नज़र में',
    glance: 'Android होम स्क्रीन विजेट, और नोटिफ़िकेशन शेड व लॉक स्क्रीन पर काउंटडाउन सूचना। लैंडस्केप मोड और बड़ी स्क्रीन के लिए अलग लेआउट हैं। काउंटडाउन को इमेज या लिंक के रूप में शेयर करें। 19 भाषाओं में उपलब्ध।',
    subs: 'मासिक या वार्षिक सदस्यता लें, या एक बार में आजीवन विकल्प खरीदें। Google Play ख़रीदने से पहले स्थानीय कीमत और शर्तें दिखाता है। सदस्यता रद्द करने तक अपने-आप नवीनीकृत होती है। योग्य वार्षिक प्लान में सात दिन मुफ़्त मिल सकते हैं; ट्रायल ख़त्म होने से पहले रद्द न करने पर दिखाई गई वार्षिक कीमत लगेगी। सदस्यताएँ Google Play में मैनेज करें। आजीवन विकल्प ख़रीदने से मौजूदा सदस्यता रद्द नहीं होती।',
    data: 'न DoneAt खाता, न विज्ञापन। रिकॉर्ड और वेतन डिफ़ॉल्ट रूप से आपके डिवाइस पर रहते हैं। Android बैकअप या नए डिवाइस पर ट्रांसफ़र में रिकॉर्ड और सेटिंग्स, वेतन सहित, शामिल हो सकते हैं। आप अपनी फ़ाइलें ख़ुद एक्सपोर्ट और इंपोर्ट कर सकते हैं; Google Drive के साथ अपने-आप सिंक नहीं होता। ख़रीद की पुष्टि Google Play और DoneAt की पुष्टि सेवा से होती है; काम के रिकॉर्ड और वेतन वहाँ नहीं भेजे जाते। विजेट, सूचनाओं और शेयर की गई इमेज या लिंक में वेतन कभी नहीं दिखता।',
    support: 'सहायता' },
  id: { asc: 'id', title: 'DoneAt - Hitung Mundur Kerja', short: 'Hitung mundur sif, jadwal kerja, cuti, dan catatan jam kerja dalam sekejap',
    glance: 'Widget Layar Utama Android dan notifikasi hitung mundur di panel notifikasi serta Layar Terkunci. Mode lanskap dan layar besar punya tata letak khusus. Bagikan hitung mundur sebagai gambar atau tautan. Tersedia dalam 19 bahasa.',
    subs: 'Berlangganan bulanan atau tahunan, atau beli akses seumur hidup sekali bayar. Google Play menampilkan harga lokal dan ketentuan sebelum pembelian. Langganan diperpanjang otomatis sampai dibatalkan. Paket tahunan yang memenuhi syarat bisa mencakup tujuh hari gratis; setelah itu harga tahunan yang tertera berlaku, kecuali dibatalkan sebelum masa uji coba berakhir. Kelola langganan di Google Play. Membeli akses seumur hidup tidak membatalkan langganan yang sedang berjalan.',
    data: 'Tanpa akun DoneAt, tanpa iklan. Secara default, catatan dan gaji tetap di perangkatmu. Cadangan Android atau pemindahan ke perangkat baru dapat menyertakan catatan dan pengaturan, termasuk gaji. Kamu bisa mengekspor dan mengimpor file sendiri; tidak ada sinkronisasi otomatis dengan Google Drive. Pembelian diverifikasi oleh Google Play dan layanan verifikasi DoneAt; catatan kerja dan gaji tidak pernah dikirim ke layanan itu. Widget, notifikasi, serta gambar dan tautan yang dibagikan tidak pernah menampilkan gaji.',
    support: 'Dukungan' },
  'it-IT': { asc: 'it', title: 'DoneAt - Conto alla rovescia', short: "Conto alla rovescia del turno, calendario, ferie e registro ore a colpo d'occhio",
    glance: "Widget della schermata Home di Android e notifica del conto alla rovescia nell'area notifiche e nella schermata di blocco. Il formato orizzontale e gli schermi grandi hanno un layout dedicato. Condividi il conto alla rovescia come immagine o link. Disponibile in 19 lingue.",
    subs: "Abbonati al mese o all'anno, oppure prendi l'accesso a vita con un unico acquisto. Google Play mostra il prezzo locale e le condizioni prima dell'acquisto. Gli abbonamenti si rinnovano automaticamente finché non li annulli. Un piano annuale idoneo può includere sette giorni gratuiti, dopo i quali si applica il prezzo annuale indicato, salvo annullamento prima della fine della prova. Gestisci gli abbonamenti in Google Play. L'acquisto dell'accesso a vita non annulla un abbonamento attivo.",
    data: "Nessun account DoneAt, niente pubblicità. Per impostazione predefinita registri e stipendio restano sul tuo dispositivo. Il backup di Android o il trasferimento su un nuovo dispositivo possono includere registri e impostazioni, stipendio compreso. Puoi esportare e importare i tuoi file; non c'è sincronizzazione automatica con Google Drive. Gli acquisti sono verificati da Google Play e dal servizio di verifica di DoneAt, che non riceve mai registri di lavoro né stipendio. Widget, notifiche e immagini o link condivisi non mostrano mai lo stipendio.",
    support: 'Assistenza' },
  'ja-JP': { asc: 'ja', title: 'DoneAt - 定時・退勤カウントダウン', short: '退勤までのカウントダウン、シフト表、休暇プラン、勤務記録をひと目で',
    glance: 'Androidのホーム画面ウィジェットに対応し、通知シェードとロック画面にはカウントダウン通知を表示できます。横向きと大画面には専用のレイアウトがあります。カウントダウンは画像やリンクで共有できます。19言語に対応しています。',
    subs: '月額・年額のサブスクリプションのほか、買い切りプランを一度だけ購入することもできます。購入前に、Google Playで現地の価格と条件が表示されます。サブスクリプションは解約するまで自動更新されます。対象の年額プランには7日間の無料期間が付く場合があり、無料期間の終了前に解約しない場合は表示された年額で更新されます。サブスクリプションはGoogle Playで管理できます。買い切りプランを購入しても、既存のサブスクリプションは自動では解約されません。',
    data: 'DoneAtのアカウント登録は不要で、広告もありません。記録と給与は標準でデバイス内に保存されます。Androidのバックアップや機種変更時のデータ移行では、給与を含む記録と設定が引き継がれることがあります。ファイルの書き出しと読み込みは自分で行えます。Googleドライブとの自動同期はありません。購入はGoogle PlayとDoneAtの確認サービスで確認され、勤務記録や給与がそのサービスに送られることはありません。ウィジェット、通知、共有する画像やリンクに給与は表示されません。',
    support: 'サポート' },
  'ko-KR': { asc: 'ko', title: 'DoneAt - 퇴근 카운트다운·교대근무', short: '퇴근 카운트다운, 근무표, 휴가 계획, 근무 기록을 한눈에',
    glance: 'Android 홈 화면 위젯과 알림 창·잠금 화면의 카운트다운 알림으로 확인해요. 가로 모드와 큰 화면에는 전용 레이아웃이 있어요. 카운트다운은 이미지나 링크로 공유할 수 있어요. 19개 언어를 지원해요.',
    subs: '월간이나 연간으로 구독할 수도 있고, 평생 이용권을 한 번만 구매할 수도 있어요. 구매 전에 Google Play에서 현지 가격과 약관을 보여 줘요. 구독은 취소할 때까지 자동 갱신돼요. 대상 연간 플랜에는 7일 무료 체험이 포함될 수 있으며, 체험 종료 전에 취소하지 않으면 표시된 연간 요금으로 갱신돼요. 구독은 Google Play에서 관리해요. 평생 이용권을 구매해도 기존 구독은 자동으로 취소되지 않아요.',
    data: 'DoneAt 계정도 광고도 없어요. 기록과 급여는 기본적으로 기기에만 저장돼요. Android 백업이나 기기 이전 시 급여를 포함한 기록과 설정이 함께 옮겨질 수 있어요. 파일은 직접 내보내고 가져올 수 있으며, Google 드라이브 자동 동기화는 없어요. 구매는 Google Play와 DoneAt 확인 서비스로 확인하며, 근무 기록과 급여는 그 서비스로 보내지 않아요. 위젯, 알림, 공유하는 이미지와 링크에는 급여가 나오지 않아요.',
    support: '지원' },
  'mr-IN': { asc: 'mr-IN', title: 'DoneAt - शिफ्ट काउंटडाउन', short: 'शिफ्ट काउंटडाउन, ड्युटीचे वेळापत्रक, सुट्ट्या आणि नोंदी एका नजरेत',
    glance: 'Android होम स्क्रीन विजेट, आणि सूचना पॅनल व लॉक स्क्रीनवर उलट मोजणी सूचना. लँडस्केप मोड आणि मोठ्या स्क्रीनसाठी स्वतंत्र लेआउट आहेत. काउंटडाउन इमेज किंवा लिंक म्हणून शेअर करा. 19 भाषांमध्ये उपलब्ध.',
    subs: 'मासिक किंवा वार्षिक सदस्यता घ्या, किंवा एकदाच आजीवन पर्याय खरेदी करा. खरेदीपूर्वी Google Play स्थानिक किंमत आणि अटी दाखवते. सदस्यता रद्द करेपर्यंत आपोआप नूतनीकृत होते. पात्र वार्षिक प्लॅनमध्ये सात दिवस मोफत मिळू शकतात; ट्रायल संपण्यापूर्वी रद्द न केल्यास दाखवलेली वार्षिक किंमत लागू होते. सदस्यता Google Play मध्ये व्यवस्थापित करा. आजीवन पर्याय खरेदी केल्याने सध्याची सदस्यता रद्द होत नाही.',
    data: 'DoneAt खाते नाही, जाहिराती नाहीत. नोंदी आणि पगार डीफॉल्टनुसार तुमच्या डिव्हाइसवरच राहतात. Android बॅकअप किंवा नवीन डिव्हाइसवर डेटा हलवताना पगारासह नोंदी आणि सेटिंग्ज समाविष्ट होऊ शकतात. तुम्ही स्वतःच्या फाइल्स एक्सपोर्ट आणि इम्पोर्ट करू शकता; Google Drive सोबत आपोआप सिंक होत नाही. खरेदीची पडताळणी Google Play आणि DoneAt च्या पडताळणी सेवेद्वारे होते; कामाच्या नोंदी आणि पगार त्या सेवेला पाठवले जात नाहीत. विजेट, सूचना आणि शेअर केलेल्या इमेज किंवा लिंकमध्ये पगार कधीच दिसत नाही.',
    support: 'सहाय्य' },
  'pt-BR': { asc: 'pt-BR', title: 'DoneAt - Fim do Expediente', short: 'Contagem do expediente, escala, folgas e registros de horas num só lugar',
    glance: 'Widgets da tela inicial do Android e uma notificação de contagem regressiva na aba de notificações e na tela de bloqueio. O modo paisagem e as telas grandes têm layouts próprios. Compartilhe a contagem como imagem ou link. Disponível em 19 idiomas.',
    subs: 'Assine por mês ou por ano, ou garanta o acesso vitalício com uma única compra. O Google Play mostra o preço local e as condições antes da compra. As assinaturas renovam automaticamente até você cancelar. Um plano anual elegível pode incluir sete dias grátis; depois vale o preço anual exibido, a menos que você cancele antes do fim do teste. Gerencie as assinaturas no Google Play. Comprar o acesso vitalício não cancela uma assinatura existente.',
    data: 'Sem conta DoneAt, sem anúncios. Por padrão, registros e salário ficam no seu dispositivo. O backup do Android ou a transferência para um novo aparelho podem incluir registros e configurações, salário incluído. Você pode exportar e importar seus próprios arquivos; não há sincronização automática com o Google Drive. As compras são verificadas pelo Google Play e pelo serviço de verificação do DoneAt, que nunca recebe seus registros de trabalho nem seu salário. Widgets, notificações e imagens ou links compartilhados nunca mostram o salário.',
    support: 'Suporte' },
  'ru-RU': { asc: 'ru', title: 'DoneAt: Таймер до конца смены', short: 'Отсчёт до конца смены, график, отпуск и учёт часов — всё перед глазами',
    glance: 'Виджеты на главном экране Android и уведомление с обратным отсчётом в шторке и на экране блокировки. Для горизонтальной ориентации и больших экранов есть отдельные макеты. Делитесь отсчётом картинкой или ссылкой. 19 языков.',
    subs: 'Подписка на месяц или на год, либо доступ навсегда одной покупкой. Google Play показывает местную цену и условия до покупки. Подписки продлеваются автоматически, пока вы их не отмените. Подходящий годовой план может включать семь бесплатных дней, после чего списывается указанная годовая цена, если не отменить подписку до конца пробного периода. Управлять подписками можно в Google Play. Покупка доступа навсегда не отменяет действующую подписку.',
    data: 'Без аккаунта DoneAt и без рекламы. По умолчанию записи и зарплата хранятся на вашем устройстве. Резервная копия Android или перенос на новое устройство могут включать записи и настройки, в том числе зарплату. Свои файлы можно экспортировать и импортировать; автоматической синхронизации с Google Диском нет. Покупки проверяются через Google Play и сервис проверки DoneAt; записи о работе и зарплата туда не отправляются. В виджетах, уведомлениях и картинках или ссылках, которыми вы делитесь, зарплаты нет.',
    support: 'Поддержка' },
  th: { asc: 'th', title: 'DoneAt - นับถอยหลังเลิกงาน', short: 'นับถอยหลังเลิกงาน ตารางกะ วางแผนวันลา และบันทึกเวลางานในที่เดียว',
    glance: 'วิดเจ็ตหน้าจอโฮมของ Android และการแจ้งเตือนนับถอยหลังในแถบการแจ้งเตือนและบนหน้าจอล็อก แนวนอนและหน้าจอใหญ่มีเลย์เอาต์เฉพาะ แชร์การนับถอยหลังเป็นภาพหรือลิงก์ได้ รองรับ 19 ภาษา',
    subs: 'สมัครรายเดือนหรือรายปีก็ได้ หรือซื้อสิทธิ์ใช้งานตลอดชีพครั้งเดียว Google Play จะแสดงราคาท้องถิ่นและเงื่อนไขก่อนซื้อ การสมัครจะต่ออายุอัตโนมัติจนกว่าจะยกเลิก แพ็กเกจรายปีที่มีสิทธิ์อาจได้ทดลองใช้ฟรี 7 วัน หลังจากนั้นจะคิดราคารายปีที่แสดง เว้นแต่ยกเลิกก่อนสิ้นสุดช่วงทดลอง จัดการการสมัครได้ใน Google Play การซื้อสิทธิ์ตลอดชีพจะไม่ยกเลิกการสมัครที่มีอยู่',
    data: 'ไม่ต้องมีบัญชี DoneAt ไม่มีโฆษณา บันทึกและเงินเดือนเก็บไว้บนอุปกรณ์ของคุณตามค่าเริ่มต้น การสำรองข้อมูลของ Android หรือการย้ายไปเครื่องใหม่อาจรวมบันทึกและการตั้งค่า รวมถึงเงินเดือน คุณส่งออกและนำเข้าไฟล์ของตัวเองได้ ไม่มีการซิงค์อัตโนมัติกับ Google ไดรฟ์ การซื้อจะได้รับการยืนยันผ่าน Google Play และบริการยืนยันของ DoneAt โดยไม่ส่งบันทึกงานหรือเงินเดือนไปยังบริการนั้น วิดเจ็ต การแจ้งเตือน และภาพหรือลิงก์ที่แชร์ไม่แสดงเงินเดือน',
    support: 'ฝ่ายสนับสนุน' },
  'tr-TR': { asc: 'tr', title: 'DoneAt: Vardiya & Mesai Sayacı', short: 'Mesai sayacı, vardiya takvimi, izin planı ve çalışma kayıtları tek bakışta',
    glance: 'Android Ana Ekran araç takımları ve bildirim panelinde ile kilit ekranında geri sayım bildirimi. Yatay mod ve büyük ekranlar için ayrı düzenler var. Geri sayımı görsel ya da bağlantı olarak paylaş. 19 dilde.',
    subs: 'Aylık ya da yıllık abone ol veya ömür boyu erişimi tek seferde satın al. Google Play satın almadan önce yerel fiyatı ve koşulları gösterir. Abonelikler iptal edene kadar otomatik yenilenir. Uygun yıllık plan yedi gün ücretsiz içerebilir; deneme bitmeden iptal etmezsen gösterilen yıllık fiyat uygulanır. Aboneliklerini Google Play\'den yönet. Ömür boyu erişim satın almak mevcut aboneliği iptal etmez.',
    data: 'DoneAt hesabı yok, reklam yok. Kayıtların ve maaşın varsayılan olarak cihazında kalır. Android yedeklemesi veya yeni cihaza aktarım, maaş dahil kayıtları ve ayarları içerebilir. Kendi dosyalarını dışa ve içe aktarabilirsin; Google Drive ile otomatik eşzamanlama yok. Satın almalar Google Play ve DoneAt doğrulama hizmetiyle doğrulanır; iş kayıtların ve maaşın bu hizmete gönderilmez. Araç takımları, bildirimler ve paylaştığın görseller ya da bağlantılar maaşını asla göstermez.',
    support: 'Destek' },
  vi: { asc: 'vi', title: 'DoneAt - Đếm ngược tan ca', short: 'Đếm ngược tan ca, lịch làm việc, kế hoạch nghỉ phép và bản ghi giờ làm',
    glance: 'Tiện ích Màn hình chính trên Android và thông báo đếm ngược trong ngăn thông báo lẫn trên Màn hình khóa. Chế độ ngang và màn hình lớn có bố cục riêng. Chia sẻ đếm ngược bằng hình ảnh hoặc liên kết. Hỗ trợ 19 ngôn ngữ.',
    subs: 'Có thể đăng ký theo tháng hoặc theo năm, hoặc mua Gói trọn đời một lần. Google Play hiển thị giá địa phương và điều khoản trước khi mua. Gói thuê bao tự động gia hạn cho đến khi bạn hủy. Gói năm đủ điều kiện có thể kèm bảy ngày miễn phí; sau đó áp dụng giá năm đã hiển thị, trừ khi bạn hủy trước khi hết thời gian dùng thử. Quản lý gói thuê bao trong Google Play. Mua Gói trọn đời không tự hủy gói thuê bao hiện có.',
    data: 'Không cần tài khoản DoneAt, không quảng cáo. Theo mặc định, bản ghi và mức lương chỉ lưu trên thiết bị của bạn. Bản sao lưu Android hoặc khi chuyển sang thiết bị mới có thể gồm bản ghi và cài đặt, kể cả mức lương. Bạn có thể tự xuất và nhập tệp của mình; không có đồng bộ tự động với Google Drive. Giao dịch mua được xác minh qua Google Play và dịch vụ xác minh của DoneAt; bản ghi công việc và mức lương không được gửi tới dịch vụ đó. Tiện ích, thông báo và hình ảnh hay liên kết chia sẻ không bao giờ hiện lương.',
    support: 'Hỗ trợ' },
  'zh-TW': { asc: 'zh-Hant', title: 'DoneAt - 下班倒數計時・班表', short: '看清這班還剩多久，安排班表與休假，回顧工時和預估收入。',
    glance: '支援 Android 主畫面小工具，以及通知欄和鎖定畫面上的倒數通知。橫向和大螢幕有專屬版面。倒數可以分享成圖片或連結。支援 19 種語言。',
    subs: '可以按月或按年訂閱，也可以一次買下終身版。Google Play 會在付款前顯示當地價格與條款。訂閱會自動續訂，直到你取消為止。符合資格的年訂閱可能包含七天免費試用，試用結束前未取消，就會依顯示的年費續訂。訂閱可在 Google Play 管理；購買終身版不會自動取消現有訂閱。',
    data: '不需要 DoneAt 帳號，沒有廣告。紀錄和薪資預設只存在你的裝置上；使用 Android 備份或換機轉移時，紀錄和設定（包含薪資）可能會一併複製。可以自行匯出、匯入檔案，不提供 Google 雲端硬碟自動同步。購買會透過 Google Play 和 DoneAt 驗證服務確認，工作紀錄和薪資不會傳到該服務。小工具、通知和分享出去的圖片、連結都不會出現薪水。',
    support: '支援', privacy: 'https://doneat.app/zh-CN/privacy' },
  'zh-HK': { asc: 'zh-Hant', title: 'DoneAt - 下班倒數計時・班表', short: '看清這更還剩多久，安排班表與放假，回顧工時和預計收入。',
    glance: '支援 Android 主畫面小工具，以及通知欄和鎖定畫面上的倒數通知。橫向和大螢幕有專屬版面。倒數可以分享成圖片或連結。支援 19 種語言。',
    subs: '可以按月或按年訂閱，也可以一次過購買終身版。Google Play 會在付款前顯示當地價格與條款。訂閱會自動續期，直至你取消為止。合資格的年費計劃可能包含七天免費試用，試用結束前未取消，便會按顯示的年費續期。訂閱可在 Google Play 管理；購買終身版不會自動取消現有訂閱。',
    data: '不需要 DoneAt 帳戶，沒有廣告。紀錄和薪金預設只存在你的裝置上；使用 Android 備份或轉機時，紀錄和設定（包括薪金）可能會一併複製。可以自行匯出、匯入檔案，不提供 Google Drive 自動同步。購買會透過 Google Play 和 DoneAt 驗證服務確認，工作紀錄和薪金不會傳送到該服務。小工具、通知和分享出去的圖片、連結都不會顯示薪金。',
    support: '支援', privacy: 'https://doneat.app/zh-CN/privacy',
    // ASC zh-Hant is written for Taiwan. Hong Kong keeps written Chinese with the app's zh-HK terms.
    replace: [['國定假日', '公眾假期'], ['規劃休假', '計劃放假'], ['休假', '放假'], ['特休', '年假'], ['薪水', '薪金'], ['薪資', '薪金'], ['隱私權政策', '私隱政策']] },
};

function adapt(lang, l) {
  const src = asc[l.asc];
  const b = src.description.split('\n\n');
  if (b.length !== 11) throw new Error(`${l.asc}: expected 11 description blocks, found ${b.length}`);
  const heading = block => block.split('\n')[0];
  const plus = b[6].split('\n').filter(line => !/iCloud/.test(line)).join('\n');
  const privacyLine = b[10].split('\n').at(-1);
  const privacy = l.privacy ? privacyLine.replace(/https:\S+/, l.privacy) : privacyLine;
  let full = [b[0], b[2], `${heading(b[3])}\n${l.glance}`, b[5], plus, l.subs, `${heading(b[8])}\n${l.data}`, `${privacy}\n${l.support}${/^(zh|ja)/.test(lang) ? '：' : ': '}hello@doneat.app`].join('\n\n');
  for (const [from, to] of l.replace || []) full = full.replaceAll(from, to);
  if (/Apple|iPhone|iPad|iCloud|Dynamic Island|Watch/.test(full)) throw new Error(`${lang}: Apple-only wording left: ${full.match(/Apple|iPhone|iPad|iCloud|Dynamic Island|Watch/)[0]}`);
  return { title: l.title, shortDescription: l.short, fullDescription: full };
}

const count = s => [...s].length;
const listings = Object.fromEntries(Object.entries(L).map(([lang, l]) => [lang, adapt(lang, l)]));
for (const [lang, v] of Object.entries(listings)) console.log(`${lang.padEnd(6)} title ${count(v.title)}/30  short ${count(v.shortDescription)}/80  full ${count(v.fullDescription)}/4000`);
if (process.argv.includes('--write')) {
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const order = ['en-US', 'en-GB', 'ar', 'de-DE', 'es-ES', 'es-419', 'fr-FR', 'hi-IN', 'id', 'it-IT', 'ja-JP', 'ko-KR', 'mr-IN', 'pt-BR', 'ru-RU', 'th', 'tr-TR', 'vi', 'zh-CN', 'zh-HK', 'zh-TW'];
  const merged = { ...config.listings, ...listings };
  config.listings = Object.fromEntries(order.map(lang => [lang, merged[lang]]));
  writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
  console.log('updated', configPath);
}
