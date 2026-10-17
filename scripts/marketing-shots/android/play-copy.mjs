// Play screenshot captions: the reviewed ASC 3.2.1/3.2.2 iPhone captions
// (../ios/creative-copy-3.2.1.mjs), in the same scene order, minus the scenes
// Android does not have (Apple Watch; Dynamic Island / Lock Screen widgets).
// zh-HK has no App Store set of its own (ASC shares zh-Hant); its captions
// follow the app's Hong Kong wording (放假, 公眾假期, colloquial Cantonese).
import {COPY as ASC} from '../ios/creative-copy-3.2.1.mjs';

// ASC page index → Play scene. ASC order: hero, detail, leave, report, watch,
// calendar, records, focus, widgets, rest.
export const SCENES=[
  {name:'01-countdown',source:'timer',kind:'hero',asc:0},
  {name:'02-countdown-detail',source:'timer',kind:'detail',asc:1},
  {name:'03-leave',source:'leave',asc:2},
  {name:'04-report',source:'report',asc:3},
  {name:'05-calendar',source:'calendar',asc:5},
  {name:'06-records',source:'records',asc:6},
  {name:'07-focus',source:'focus',asc:7},
  {name:'08-breaks',source:'breaks',asc:9},
];

const P=(label,title,sub='')=>({label,lines:title.split('|'),sub:sub?sub.split('|'):[]});
const HK={
  hero:'下班，|值得|期待。',intro:'你的時間，|唔止屬於工作。',note:'畫面為示範資料',
  pages:[
    null,
    P('每一秒，都離收工近啲。',''),
    P('計劃放假 · 3 次免費體驗','請幾日假，|放得更長。','請邊幾日，可以連放幾耐。|放入月曆，一眼睇清。'),
    P('週期報告 · DoneAt Plus','忙過嘅日子，|慢慢睇清。','工作、加班同休息，|寫成你嘅週報、月報同年報。'),
    null,
    P('月曆排班 · 公眾假期','邊日返工，|一眼睇清。','排班一改，月曆即刻更新。|開啟地區範本，一齊安排公眾假期。'),
    P('紀錄 · DoneAt Plus 年檢視','忙過嘅日子，|都有跡可尋。','用顏色回顧一年嘅工時，|睇清自己嘅工作節奏。'),
    P('番茄鐘 · DoneAt Plus','專心一陣，|再抖一陣。','將待辦放入專注時段，|工作同休息，各有節奏。'),
    null,
    P('留啲空間俾休息','中途休息，|唔計工時。','自動扣除休息時段，按實際工時倒數。'),
  ],
};

/** Captions for one app language, in Play order. */
export function playPages(lang){
  if(lang==='zh-HK')return SCENES.map(s=>({...s,...(s.kind==='hero'?{label:'DoneAt',lines:HK.hero.split('|'),sub:HK.intro.split('|'),foot:HK.pages[1].label}:HK.pages[s.asc]),note:HK.note}));
  const c=ASC[lang];
  if(!c)throw Error('No ASC captions for '+lang);
  return SCENES.map(s=>{
    const page=s.kind==='hero'?{label:'DoneAt',lines:c.hero,sub:c.intro.split('|'),foot:c.pages[1].label}:{label:c.pages[s.asc].label,lines:c.pages[s.asc].lines,sub:c.pages[s.asc].sub};
    return {...s,...page,note:c.note};
  });
}

/** Focus task titles shown in the capture, in the storefront language. */
export const demoTasks=lang=>lang==='zh-HK'?['整理項目資料','完成設計方案','回覆工作電郵']:ASC[lang].demoTasks;

// App language → Play languages that use its screenshots. en-GB and es-419
// reuse en-US and es-ES, as ASC's en-GB and es-MX fall back to them.
export const PLAY_TARGETS={en:['en-US','en-GB'],es:['es-ES','es-419'],de:['de-DE'],fr:['fr-FR'],it:['it-IT'],pt:['pt-BR'],ja:['ja-JP'],ko:['ko-KR'],ru:['ru-RU'],tr:['tr-TR'],id:['id'],vi:['vi'],th:['th'],'hi-IN':['hi-IN'],'mr-IN':['mr-IN'],ar:['ar'],'zh-CN':['zh-CN'],'zh-TW':['zh-TW'],'zh-HK':['zh-HK']};
