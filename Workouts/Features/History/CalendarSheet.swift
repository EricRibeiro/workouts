//
//  CalendarSheet.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// The History Calendar (task 5.4): a month grid, Monday first, with the days that have a finished workout marked by a
/// tinted circle and today outlined. Previous / Next month move the grid. A marked day with one workout opens it; with
/// several, the day is selected and its workouts are listed under the grid to pick from. Done is in the Close slot.
/// Days are cut in the device calendar, so a time zone change regroups them.
struct CalendarSheet: View {
    /// The finished workouts (id, name, start).
    let entries: [HistoryEntry]
    /// Opens a workout; the presenter dismisses the sheet and pushes it.
    let open: (UUID) -> Void
    var calendar: Calendar = .current

    @Environment(\.dismiss) private var dismiss
    @State private var month: Date
    @State private var selectedDay: Date?

    init(
        entries: [HistoryEntry],
        month: Date = .now,
        calendar: Calendar = .current,
        open: @escaping (UUID) -> Void
    ) {
        self.entries = entries
        self.calendar = calendar
        self.open = open
        _month = State(initialValue: CalendarMonth.shift(month, by: 0, calendar: calendar))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let counts = CalendarMonth.workoutCounts(entries.map(\.startedAt), calendar: calendar)
        let rows = CalendarMonth.monthGrid(for: month, calendar: calendar)
        let monthHasWorkouts = rows.flatMap { $0 }.contains { day in
            day.map { counts[CalendarMonth.day(of: $0, calendar: calendar)] != nil } ?? false
        }

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(CalendarMonth.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                            Text(initial)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        ForEach(Array(rows.flatMap { $0 }.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day, count: counts[CalendarMonth.day(of: day, calendar: calendar)] ?? 0)
                            } else {
                                Color.clear.frame(height: 1).accessibilityHidden(true)
                            }
                        }
                    }
                    // Seven columns cannot hold accessibility-size digits; Calendar.app caps its grid the same way.
                    // Every day's accessibility label still carries the full date.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    footer(monthHasWorkouts: monthHasWorkouts)
                    if let selectedDay { dayWorkouts(selectedDay) }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("calendar.done")
                }
            }
        }
        .accessibilityIdentifier("screen.calendar")
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") { move(by: -1) }
                .accessibilityIdentifier("calendar.prev")
            Spacer()
            Text(CalendarMonth.title(for: month, calendar: calendar))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendar.title")
            Spacer()
            Button("Next month", systemImage: "chevron.right") { move(by: 1) }
                .accessibilityIdentifier("calendar.next")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }

    private func move(by months: Int) {
        month = CalendarMonth.shift(month, by: months, calendar: calendar)
        selectedDay = nil
    }

    // MARK: Days

    @ViewBuilder
    private func dayCell(_ day: Date, count: Int) -> some View {
        let label = CalendarMonth.accessibilityLabel(for: day, workouts: count, calendar: calendar)
        let identifier = "calendar.day.\(CalendarMonth.identifier(for: day, calendar: calendar))"
        if count > 0 {
            // Marked: a button that opens the day's workout (or lists them).
            Button {
                tap(day, count: count)
            } label: {
                dayNumber(day, marked: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
        } else {
            // Nothing to open: plain text, not a dead control.
            dayNumber(day, marked: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }

    private func dayNumber(_ day: Date, marked: Bool) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay == day
        return Text(day, format: .dateTime.day())
            .font(.body.weight(marked || isToday ? .semibold : .regular))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(marked ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if marked { Circle().fill(.tint) }
            }
            .overlay {
                if isToday { Circle().strokeBorder(.tint, lineWidth: 2) }
                if isSelected { Circle().strokeBorder(.primary, lineWidth: 2).padding(-3) }
            }
            .contentShape(Rectangle())
    }

    private func tap(_ day: Date, count: Int) {
        let workouts = workouts(on: day)
        if let only = workouts.first, workouts.count == 1 {
            open(only.id)
        } else if count > 1 {
            selectedDay = day
        }
    }

    private func workouts(on day: Date) -> [HistoryEntry] {
        let key = CalendarMonth.day(of: day, calendar: calendar)
        return
            entries
            .filter { CalendarMonth.day(of: $0.startedAt, calendar: calendar) == key }
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(monthHasWorkouts: Bool) -> some View {
        Text(monthHasWorkouts ? "Tap a marked day to open its workout." : "No workouts this month.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("calendar.hint")
    }

    /// The workouts of a selected day with several, each a row that opens it.
    private func dayWorkouts(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.headline)
                .padding(.vertical, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(workouts(on: day)) { entry in
                Button {
                    open(entry.id)
                } label: {
                    HStack {
                        Text(entry.name)
                        Spacer()
                        Text(entry.startedAt, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendar.workout.\(entry.id.uuidString)")
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

#if DEBUG
    /// Hosts the sheet's content for the gallery, over the sample workouts.
    struct CalendarDemo: View {
        @Query(
            filter: #Predicate<Workout> { $0.finishedAt != nil },
            sort: \Workout.startedAt,
            order: .reverse
        ) private var finished: [Workout]

        var body: some View {
            CalendarSheet(
                entries: finished.map {
                    HistoryEntry(
                        id: $0.id,
                        name: $0.name,
                        startedAt: $0.startedAt,
                        durationSeconds: 0,
                        volume: 0,
                        unit: .kg,
                        prCount: 0,
                        exerciseNames: []
                    )
                },
                open: { _ in }
            )
        }
    }
#endif
