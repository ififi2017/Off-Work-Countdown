import Foundation

// Inputs only. WeekProgress, CalendarProgress and LifeFigures are extracted
// verbatim from their real iOS widget source files by the generator.
// Never put a second calculation or an expected answer in this harness.

func at(_ day: String, _ hour: Int = 0, zone: String = "UTC") -> Int64 {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH"; f.timeZone = TimeZone(identifier: zone)!
    return Int64(f.date(from: String(format: "%@ %02d",day,hour))!.timeIntervalSince1970 * 1000)
}
func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970:Double(ms)/1000) }
var out: [String: Any] = [:]
let monday = WidgetCalendarDay(dayKey:"2026-10-26",startMs:at("2026-10-26"),kind:.work,title:nil,colorHex:nil,segments:[[at("2026-10-26",9),at("2026-10-26",12)],[at("2026-10-26",13),at("2026-10-26",17)]],cycleDay:nil,cycleLength:nil)
let tuesday = WidgetCalendarDay(dayKey:"2026-10-27",startMs:at("2026-10-27"),kind:.work,title:nil,colorHex:nil,segments:[[at("2026-10-27",22),at("2026-10-28",6)]],cycleDay:nil,cycleLength:nil)
let payload = WidgetCalendarPayload(generatedAtMs:at("2026-10-26"),locale:"en",timeZoneIdentifier:"UTC",firstWeekday:2,scheduleKind:.weekly,days:[monday,tuesday,WidgetCalendarDay(dayKey:"2026-10-28",startMs:at("2026-10-28"),kind:.rest,title:nil,colorHex:nil,segments:[],cycleDay:nil,cycleLength:nil)],labels:[: ])
out["week"] = [at("2026-10-26",12),at("2026-10-26",13),at("2026-10-28",2)].map { now -> [String:Any] in
    let p = WeekProgress(payload:payload,atMs:now)
    return ["nowMs":now,"totalMs":p.totalMs,"remainingMs":p.remainingMs,"remainingDays":p.remainingDays,"progress":p.progress]
}
out["calendar"] = ["2026-03-08","2026-11-01"].map { day -> [String:Any] in
    var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(identifier:"America/Los_Angeles")!; c.firstWeekday=1
    let now=at(day,12,zone:"America/Los_Angeles")
    let p=CalendarProgress(date:date(now),calendar:c)
    return ["nowMs":now,"today":p.today,"week":p.week,"month":p.month,"year":p.year,"daysLeftInYear":p.daysLeftInYear]
}
out["life"] = ["UTC","Pacific/Kiritimati","Pacific/Auckland"].map { zone -> [String:Any] in
    NSTimeZone.default = TimeZone(identifier:zone)!
    let now=at("2026-10-28",10,zone:zone)
    let today=Int(floor(Calendar.current.startOfDay(for:date(now)).timeIntervalSince1970/86400+0.5))
    let p=WidgetLifePayload(generatedAtMs:now,locale:"en",access:WidgetAccess(plus:true,validUntilMs:nil),bornDay:today-10000,bornIsApproximate:false,careerStartDay:today-1000,retirementDay:today+2000,lifeYears:80,hidesExactAges:false,labels:[:])
    let f=LifeFigures(payload:p,date:date(now))!
    return ["zone":zone,"nowMs":now,"todayOrdinal":today,"daysLived":f.daysLived,"lifeShare":f.lifeShare,"careerShare":f.careerShare!,"ageMonths":f.ageMonths,"monthsWorked":f.monthsWorked!,"monthsToRetirement":f.monthsToRetirement!]
}
let data=try JSONSerialization.data(withJSONObject:out,options:[.prettyPrinted,.sortedKeys])
print(String(data:data,encoding:.utf8)!)
