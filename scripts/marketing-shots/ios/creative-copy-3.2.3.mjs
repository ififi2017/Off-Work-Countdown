// Headlines for the 3.2.3 search-results video. The widget suite gets three
// beats of its own (Home Screen twice, then the Lock Screen); every other beat
// keeps its reviewed 3.2.2 line. Only zh-CN and en are written so far; the new
// lines are listed in app-store-connect/ios/3.2.3/search-video.md for review.
import {searchLine as line322} from './creative-copy-3.2.2.mjs';

const WRITTEN={
 'zh-CN':{home:['不用打开，','桌面就有数。'],desk:['班表和本周，','一眼看清。'],lock:['锁屏一亮，','还剩多久。']},
 en:{home:['Your day,','on your Home Screen.'],desk:['Your shifts.','Your week.'],lock:['Wake your screen.','See what’s left.']},
};

export const LOCALES=Object.keys(WRITTEN);

/** [dark, accent] for a scene, and where it came from. */
export function searchLine(locale,scene){
 const own=WRITTEN[locale]?.[scene];
 if(own)return{lines:own,source:'written for 3.2.3'};
 return line322(locale,scene);
}
