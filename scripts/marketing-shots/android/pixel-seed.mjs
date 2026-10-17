// Synthetic archives for the Play screenshots, ported from the iOS 3.2.1/3.2.2
// marketing seeds (../ios/creative-seed-3.2.1.mjs). They start from the same
// iOS demo archive, so Android and App Store pages describe the same fictional
// history. Only ever written into the isolated `.shots` Debug install.
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {demoTasks} from './play-copy.mjs';

const uuid=()=>randomUUID().toUpperCase();
const ZONE='Asia/Shanghai';
export const workNames={'zh-CN':['白班','休息'],'zh-TW':['日班','休息'],'zh-HK':['日更','休息'],en:['Day','Rest'],de:['Tag','Frei'],fr:['Jour','Repos'],es:['Día','Libre'],it:['Giorno','Riposo'],pt:['Dia','Folga'],ja:['日勤','休み'],ko:['주간','휴무'],ru:['День','Отдых'],tr:['Gündüz','İzin'],id:['Siang','Libur'],vi:['Ca ngày','Nghỉ'],th:['กะกลางวัน','หยุด'],'hi-IN':['दिन','आराम'],'mr-IN':['दिवस','विश्रांती'],ar:['نهاري','راحة']};
const hoursData=hours=>Buffer.from(JSON.stringify(hours)).toString('base64');
// Local civil date and epoch helpers in the demo zone (the Pixel runs in it too).
const civil=(ms=Date.now())=>new Intl.DateTimeFormat('en-CA',{timeZone:ZONE,year:'numeric',month:'2-digit',day:'2-digit'}).format(ms);
const at=(day,h,m=0)=>Date.parse(`${day}T${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:00+08:00`);

export function loadDemo(path){
  const local=JSON.parse(readFileSync(path,'utf8'));
  return JSON.parse(Buffer.from(local.document,'base64').toString('utf8'));
}

/** The base every scene shares: regular Mon–Fri 09:00–17:00 with lunch, as iOS regularSeed. */
function regular(doc,lang,{workdays}={}){
  const a=structuredClone(doc);
  const days=workdays||(lang==='ar'?[0,1,2,3,4]:[1,2,3,4,5]);
  a.focusSessions=[];a.focusTasks=[];delete a.focusPlanningConfiguration;delete a.extendedSchedule;
  a.timeZoneIdentifier=ZONE;a.leaveBalances=[];a.leaveDays=[];
  Object.assign(a.syncedPreferences,{recordsTimeZoneIdentifier:ZONE,languageOverride:lang==='zh-HK'?'zh-HK':lang,startMinutes:540,endMinutes:1020,workdays:days,scheduleMode:'classic',lunchEnabled:true,lunchStartMinutes:720,lunchDurationMinutes:60,theme:'light',
    salaryEnabled:true,salaryType:'monthly',salaryAmount:'12000',monthlyWorkingDays:22,lunchStartReminderEnabled:false,lunchEndReminderEnabled:false});
  a.careerPeriods.forEach(p=>{p.timeZoneIdentifier=ZONE;p.startsOn='2025-01-01';});a.recordsStartedOn='2025-01-01';
  const hours={startTime:'09:00',endTime:'17:00',workdays:days,schedule:{mode:'classic'},breakStartTime:'12:00',breakDurationMinutes:60};
  a.scheduleSnapshots.forEach(s=>{s.effectiveFrom='2025-01-01';s.configurationData=hoursData(hours);});
  return a;
}

/** Today is a working day 09:00–18:00 with lunch 12:00–13:00, whatever weekday the capture runs on (iOS focusSeed hours). */
function everyDay(doc,lang){
  const a=regular(doc,lang,{workdays:[0,1,2,3,4,5,6]});
  Object.assign(a.syncedPreferences,{endMinutes:1080});
  const hours={startTime:'09:00',endTime:'18:00',workdays:[0,1,2,3,4,5,6],schedule:{mode:'classic'},breakStartTime:'12:00',breakDurationMinutes:60};
  a.scheduleSnapshots.forEach(s=>{s.configurationData=hoursData(hours);});
  return a;
}

/** Weekly roster with the storefront region's public holidays (iOS calendarSeed). */
function calendar(doc,lang,region){
  const a=regular(doc,lang),now=Date.now();
  a.dayOverrides=[];a.rosterDays=[];a.calendarExceptions=[];
  const work=uuid(),rest=uuid(),weekend=region==='SA';
  const make=(kind,index,id)=>({id,name:workNames[lang][index],kind,startMinutes:540,endMinutes:1020,breakEnabled:kind==='work',breakStartMinutes:720,breakDurationMinutes:60,colorHex:kind==='work'?'#F45A1E':'#69B792',isArchived:false});
  a.extendedSchedule={isEnabled:true,shiftTypes:[make('work',0,work),make('rest',1,rest)],rule:{preset:'weekly',anchorDayKey:'2026-01-05',days:weekend?[work,work,work,work,rest,rest,work]:[work,work,work,work,work,rest,rest]},holidayRegionIdentifier:region,timeZoneIdentifier:ZONE,editedAtMs:now,editCount:1,editTieBreaker:uuid()};
  const days=weekend?[0,1,2,3,4]:[1,2,3,4,5];
  const hours={startTime:'09:00',endTime:'17:00',workdays:days,schedule:{mode:'classic'},breakStartTime:'12:00',breakDurationMinutes:60,extendedContent:{shiftTypes:a.extendedSchedule.shiftTypes,rule:a.extendedSchedule.rule,holidayRegionIdentifier:region}};
  a.scheduleSnapshots.forEach(s=>{s.configurationData=hoursData(hours);});
  a.syncedPreferences.workdays=days;
  return a;
}

/** A running 25-minute focus block in a populated day (iOS focusSeed). */
function focus(doc,lang){
  const a=everyDay(doc,lang),now=Date.now(),day=civil(now);
  const tasks=demoTasks(lang);
  a.focusTasks=tasks.map((title,i)=>({id:i===0?'00000000-0026-4000-A000-000000000320':uuid(),title,icon:'focus',createdAtMs:now,editedAtMs:now,editCount:1,editTieBreaker:uuid(),estimatedPomodoros:1,isFavorite:false,plannedForDate:day,scheduledStartAtMs:at(day,14+i),sortIndex:i}));
  a.focusSessions=[{id:uuid(),taskID:a.focusTasks[0].id,kind:'focus',timeZoneIdentifier:ZONE,shiftAnchorDate:day,startedAtMs:now-3*60000,plannedEndAtMs:now+22*60000,plannedEndReason:'completed',editedAtMs:now,editCount:1,editTieBreaker:uuid()}];
  const assignments=[[9,0],[9,30],[10,0],[10,30],[11,10],[11,40],[13,0],[13,30],[14,0],[14,40],[15,10],[15,40],[16,10],[16,50],[17,20]].map(([h,m],i)=>{const t=a.focusTasks[i<8?1:i<12?0:2];return{blockStartAtMs:at(day,h,m),kind:'task',taskID:t.id,taskTitle:t.title,taskIcon:'focus'};});
  a.focusPlanningConfiguration={plans:[{dayKey:day,shiftStartAtMs:at(day,9),assignments}],templates:[],autoAppliedDayKeys:[day],focusMinutes:25,shortBreakMinutes:5,longBreakMinutes:15,longBreakEvery:4,editedAtMs:now,editCount:1,editTieBreaker:uuid()};
  return a;
}

/** Leave: a regular week with the region's holidays and an annual-leave balance to plan with. */
function leave(doc,lang,region){
  const a=calendar(doc,lang,region),now=Date.now();
  a.leaveBalances=[{id:uuid(),kind:'annual',entitledHalfDays:20,usedHalfDays:0,validFromDayKey:'2026-01-01',validThroughDayKey:'2027-03-31',editedAtMs:now,editCount:1,editTieBreaker:uuid()}];
  return a;
}

export function seedDocument(doc,lang,scene,region){
  const now=Date.now();
  let a;
  switch(scene){
    case 'timer':case 'breaks':a=everyDay(doc,lang);break;
    case 'focus':a=focus(doc,lang);break;
    case 'calendar':a=calendar(doc,lang,region);break;
    case 'leave':a=leave(doc,lang,region);break;
    case 'records':case 'report':a=regular(doc,lang);break;
    default:throw Error('Unknown scene '+scene);
  }
  a.exportedAtMs=now;
  a.syncedPreferences.editedAtMs=now;a.syncedPreferences.editCount=(a.syncedPreferences.editCount||1)+1;a.syncedPreferences.editTieBreaker=uuid();
  return a;
}

/** The Android local archive file (RecordArchive): the schema-7 document in base64 plus tombstones. */
export const localFile=a=>JSON.stringify({schemaVersion:7,document:Buffer.from(JSON.stringify(a)).toString('base64'),erased:[],importConflicts:[]});
