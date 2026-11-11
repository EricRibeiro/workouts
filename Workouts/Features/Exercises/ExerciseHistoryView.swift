//
//  ExerciseHistoryView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The History segment (task 4.3): the exercise's sessions newest first, each a card with the workout name and date as
/// its header and its completed sets as rows (`docs/port/screens/exercises.md` section 2, "History tab"). Lazy, so a
/// long history only builds the cards on screen. The header opens the workout in the History tab; the embedded pane
/// (the logging screen's exercise pane, over the active workout's cover) keeps it plain text, because switching tabs
/// behind the cover would change nothing the user can see.
struct ExerciseHistoryView: View {
    let sessions: [ExerciseHistorySession]
    var embedded = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @ScaledMetric(relativeTo: .body) private var labelWidth = Metrics.setLabelWidth

    var body: some View {
        if sessions.isEmpty {
            Text("No history yet. Log a workout with this exercise to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("exerciseDetail.history.empty")
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(sessions) { session in
                    card(session)
                }
            }
        }
    }

    private func card(_ session: ExerciseHistorySession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            openableHeader(session)
            ForEach(session.sets) { set in
                Divider()
                row(set, in: session)
            }
        }
        .detailCardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exerciseDetail.history.session.\(session.id)")
    }

    @ViewBuilder
    private func openableHeader(_ session: ExerciseHistorySession) -> some View {
        if !embedded, let navigation {
            Button {
                navigation.openWorkout(session.workoutID)
            } label: {
                header(session, opens: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
            .accessibilityIdentifier("exerciseDetail.history.session.\(session.id).open")
        } else {
            header(session, opens: false)
                .padding(.vertical, 10)
        }
    }

    private func header(_ session: ExerciseHistorySession, opens: Bool) -> some View {
        let date = RecordFormat.date(session.time)
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.workoutName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(date).font(.footnote).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if session.prCount > 0 {
                Label {
                    Text(session.prCount == 1 ? "1 PR" : "\(session.prCount) PRs")
                } icon: {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(Color.record)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            }
            if opens {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                session.workoutName, date,
                session.prCount > 0
                    ? (session.prCount == 1 ? "1 personal record" : "\(session.prCount) personal records") : nil,
            ].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityHint(opens ? "Opens \(session.workoutName) from \(date) in History" : "")
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ set: ExerciseHistorySet, in session: ExerciseHistorySession) -> some View {
        let spoken = [
            set.kind == .normal ? "Set \(set.label)" : "\(Self.kindName(set.kind)) set",
            set.text,
            set.isPR ? "personal record" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(set.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(set.kind == .normal ? Color.secondary : set.kind.color)
                .frame(width: labelWidth, alignment: .leading)
            Text(set.text)
                .font(.body)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if set.isPR {
                Image(systemName: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.record)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("exerciseDetail.history.session.\(session.id).set.\(set.id)")
    }

    private static func kindName(_ kind: SetKind) -> String {
        switch kind {
        case .normal: "Normal"
        case .warmup: "Warm-up"
        case .drop: "Drop"
        case .failure: "Failure"
        }
    }
}
