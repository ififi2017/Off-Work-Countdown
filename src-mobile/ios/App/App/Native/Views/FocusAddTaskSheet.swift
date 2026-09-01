import SwiftUI

struct FocusAddTaskSheet: View {
    let store: OffWorkStore
    var onSaved: () -> Void = {}
    @State private var title = ""
    @State private var icon = FocusTaskIcon.focus
    @State private var isFavorite = false
    @State private var startNow = true
    @State private var selectedSlot: FocusScheduleSlot?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slots: [FocusScheduleSlot] { store.focusScheduleSlots() }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (startNow || selectedSlot != nil)
    }

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.t("focusTaskTitle"))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(OWCDesign.secondary)
                        HStack(spacing: 10) {
                            Image(systemName: icon.systemName)
                                .foregroundStyle(titleFocused ? OWCDesign.accent : OWCDesign.secondary)
                                .accessibilityHidden(true)
                            TextField(store.t("focusTaskPlaceholder"), text: $title)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .accessibilityLabel(store.t("focusTaskTitle"))
                                .focused($titleFocused)
                                .textInputAutocapitalization(.sentences)
                                .submitLabel(.done)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .background(
                            titleFocused ? OWCDesign.accent.opacity(0.08) : OWCDesign.control,
                            in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                                .strokeBorder(
                                    titleFocused ? OWCDesign.accent.opacity(0.72) : OWCDesign.separator,
                                    lineWidth: titleFocused ? 1.5 : 1
                                )
                        }
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 14)
                    .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.press, value: titleFocused)
                    FocusTaskIconPicker(store: store, selection: $icon)
                        .padding(.horizontal, OWCDesign.pageInset)

                    Button {
                        isFavorite.toggle()
                    } label: {
                        Label(
                            store.t(isFavorite ? "focusFavoriteOn" : "focusMakeFavorite"),
                            systemImage: isFavorite ? "star.fill" : "star"
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isFavorite ? OWCDesign.orangeDeep : OWCDesign.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, OWCDesign.pageInset)

                    OWCGroupCard {
                        Button {
                            startNow = true
                        } label: {
                            OWCRow(icon: "play.fill", title: store.t("focusStartNow")) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(OWCDesign.accent)
                                    .opacity(startNow ? 1 : 0)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())

                        Button {
                            startNow = false
                            if selectedSlot == nil { selectedSlot = slots.first }
                        } label: {
                            OWCRow(icon: "calendar", title: store.t("focusSchedule"), isLast: slots.isEmpty) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(OWCDesign.accent)
                                    .opacity(startNow ? 0 : 1)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())

                        if !startNow {
                            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                                Button {
                                    selectedSlot = slot
                                } label: {
                                    OWCRow(
                                        title: store.t(
                                            "focusScheduleSegment",
                                            values: ["label": slotLabel(slot)]
                                        ),
                                        isLast: index == slots.count - 1
                                    ) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(OWCDesign.accent)
                                            .opacity(selectedSlot == slot ? 1 : 0)
                                    }
                                }
                                .buttonStyle(OWCRowButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                }
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t("focusAddTask"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("focusSaveTask"), action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                titleFocused = true
                selectedSlot = slots.first
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func slotLabel(_ slot: FocusScheduleSlot) -> String {
        OWCText.ltrRange(store.formatRecordsTime(slot.start), store.formatRecordsTime(slot.end))
    }

    private func save() {
        if startNow {
            store.addAndStartFocusTask(title: title, icon: icon, isFavorite: isFavorite)
        } else if let selectedSlot {
            store.addScheduledFocusTask(
                title: title,
                slot: selectedSlot,
                icon: icon,
                isFavorite: isFavorite
            )
        }
        dismiss()
        onSaved()
    }
}
