import SwiftUI
import UIKit

/// "Daily pay by month": this month's daily pay, the calendar it is divided by,
/// and the next three months (plan 024). Reached from the salary page, which
/// owns the unlock; this page is only ever pushed from its unlocked content and
/// is popped by it whenever the app resigns active, so the figures never reach
/// the app switcher. Every figure comes from `MonthlyDailyPay`.
struct MonthlyDailyPayView: View {
    @Bindable var shifts: ShiftSessionStore
    /// Covers the page the instant the app resigns active, before the salary
    /// page behind it has popped this one.
    @State private var covered = false

    private var text: AppText { shifts.text }

    var body: some View {
        let now = Date.now
        let calendar = shifts.preferences.recordsCalendar
        let pay = MonthlyDailyPay.make(
            rules: shifts.session.rulesInput(at: now), now: now, firstWeekday: calendar.firstWeekday
        )

        Group {
            if let pay, !covered {
                content(pay, calendar: calendar)
            } else {
                OWCDesign.page
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("monthlyDailyPayTitle"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .owcDetailBack(title: text.t("salarySettings"), pageTitle: text.t("monthlyDailyPayTitle"))
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            covered = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            covered = false
        }
    }

    private func content(_ pay: MonthlyDailyPay, calendar: Calendar) -> some View {
        OWCContentSizedScrollView {
            VStack(spacing: 0) {
                summaryCard(pay, calendar: calendar)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 22)

                VStack(alignment: .leading, spacing: 0) {
                    OWCSectionHeader(title: text.t("monthlyDailyPayUpcoming"))
                    OWCGroupCard {
                        ForEach(Array(pay.upcoming.enumerated()), id: \.element.id) { index, month in
                            OWCRow(
                                title: monthName(month.startMs, pay.timeZone),
                                subtitle: text.t("scheduledMonthWorkdays", values: ["count": text.formatCount(month.workdayCount)]),
                                isLast: index == pay.upcoming.count - 1,
                                centersVertically: true
                            ) {
                                Text(text.moneyText(month.dailyPay))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(OWCDesign.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 20)

                Text(text.t("monthlyDailyPayNote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.top, 8)

                Spacer(minLength: 8)
            }
        }
    }

    private func summaryCard(_ pay: MonthlyDailyPay, calendar: Calendar) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(monthName(pay.current.startMs, pay.timeZone))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Text(text.moneyText(pay.current.dailyPay))
                    .font(.largeTitle.bold().monospacedDigit())
                    .tracking(-0.5)
                if pay.current.workdayCount >= 1 {
                    Text("\(text.moneyText(pay.monthlyAmount)) ÷ \(text.t("scheduledMonthWorkdays", values: ["count": text.formatCount(pay.current.workdayCount)]))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            monthGrid(pay, calendar: calendar)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }

    private func monthGrid(_ pay: MonthlyDailyPay, calendar: Calendar) -> some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        // Headers, blanks and days used to share one grid with overlapping Int
        // ids (0–6, 0–n, 1–31), so SwiftUI dropped days 1–6 as duplicates.
        // Keep the headers in their own row and give blanks negative ids.
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    Text(symbols[(calendar.firstWeekday - 1 + column) % 7])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(-pay.leadingBlanks..<0, id: \.self) { _ in
                    Color.clear.frame(height: 34)
                }
                ForEach(pay.days) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: MonthlyDailyPay.Day) -> some View {
        Text(day.id.formatted(.number.locale(shifts.preferences.locale)))
            .font(.footnote.monospacedDigit().weight(day.isToday ? .semibold : .regular))
            .foregroundStyle(day.isToday && day.isWorkday ? Color.white : (day.isWorkday ? OWCDesign.primary : OWCDesign.tertiary))
            .frame(width: 32, height: 32)
            .background {
                if day.isToday && day.isWorkday {
                    Circle().fill(OWCDesign.accent)
                } else if day.isWorkday {
                    Circle().fill(OWCDesign.recordsWork.opacity(0.16))
                }
            }
            .overlay {
                if day.isToday && !day.isWorkday {
                    Circle().strokeBorder(OWCDesign.accent, lineWidth: 1.5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(day.id.formatted(.number.locale(shifts.preferences.locale))), \(text.t(day.isWorkday ? "extendedKindWork" : "extendedKindRest"))")
    }

    private func monthName(_ ms: Double, _ timeZone: TimeZone) -> String {
        Date(timeIntervalSince1970: ms / 1_000).formatted(
            Date.FormatStyle(locale: shifts.preferences.locale, timeZone: timeZone).year().month(.wide)
        )
    }
}
