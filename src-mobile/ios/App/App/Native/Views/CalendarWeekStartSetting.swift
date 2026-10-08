import SwiftUI

struct CalendarWeekStartSetting: View {
    @Bindable var preferences: PreferencesStore
    let text: AppText

    var body: some View {
        Menu {
            Picker(text.t("calendarWeekStart"), selection: Binding(
                get: { preferences.recordsCalendar.firstWeekday },
                set: { preferences.setCalendarFirstWeekday($0) }
            )) {
                Text(weekdayName(1)).tag(1)
                Text(weekdayName(2)).tag(2)
            }
        } label: {
            OWCRow(icon: "calendar", title: text.t("calendarWeekStart")) {
                OWCDetailAccessory(text: weekdayName(preferences.recordsCalendar.firstWeekday))
            }
        }
        .buttonStyle(OWCRowButtonStyle())
        .sensoryFeedback(.selection, trigger: preferences.calendarFirstWeekday)
    }

    private func weekdayName(_ weekday: Int) -> String {
        preferences.recordsCalendar.standaloneWeekdaySymbols[weekday - 1]
    }
}
