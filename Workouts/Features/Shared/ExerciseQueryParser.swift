//
//  ExerciseQueryParser.swift
//  Workouts
//

import FoundationModels
import SwiftUI
import WorkoutsKit

/// Turns a typed sentence into an `ExerciseQuery` (task 4.6). Behind a protocol so previews and UI tests can stub it.
protocol ExerciseQueryParsing: Sendable {
    /// Gets a session ready for `parse`; called when the Exercises tab or the picker appears. Cheap to call repeatedly.
    func prewarm(store: ExerciseStore)
    /// The structured query for `text`, or nil when the model is unavailable or anything goes wrong (guardrail, decode
    /// error, cancellation) or nothing useful came out. Never throws: the caller falls back to the plain search.
    func parse(_ text: String) async -> ExerciseQuery?
}

/// The `@Generable` mirror of the kit's `ExerciseQuery`. Facet values are drawn from the catalog vocabulary, which is
/// listed in the session instructions at runtime (so the guides stay generic).
@Generable
struct GeneratedExerciseQuery {
    @Guide(
        description: "Body parts the request is about, each exactly as written in the body part list. Empty if none."
    )
    var bodyParts: [String]
    @Guide(
        description:
            "Equipment categories the request names, each exactly as written in the equipment list. Usually empty."
    )
    var categories: [String]
    @Guide(description: "Equipment the request names, each exactly as written in the equipment list. Empty if none.")
    var equipment: [String]
    @Guide(
        description:
            "Words that belong in the exercise name, such as press, curl or row. Leave out body parts, equipment and filler words."
    )
    var words: [String]

    var query: ExerciseQuery {
        ExerciseQuery(bodyParts: bodyParts, categories: categories, equipment: equipment, words: words)
    }
}

/// The Foundation Models implementation. Holds one prewarmed session; each parse consumes it and queues a fresh one, so
/// a query never sees an earlier query's transcript.
final class ExerciseQueryParser: ExerciseQueryParsing {
    private var instructions: String?
    private var session: LanguageModelSession?

    private var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func prewarm(store: ExerciseStore) {
        guard isAvailable else { return }
        if instructions == nil { instructions = Self.instructions(for: store) }
        if session == nil { makeSession()?.prewarm() }
    }

    func parse(_ text: String) async -> ExerciseQuery? {
        guard isAvailable, let session = takeSession() else { return nil }
        defer { makeSession()?.prewarm() }
        do {
            let response = try await session.respond(to: text, generating: GeneratedExerciseQuery.self)
            let query = response.content.query
            return query.isEmpty ? nil : query
        } catch {
            return nil
        }
    }

    /// Replaces the stored session with a fresh one and returns it; nil until `prewarm` has supplied the vocabulary.
    @discardableResult
    private func makeSession() -> LanguageModelSession? {
        guard let instructions else { return nil }
        let fresh = LanguageModelSession(instructions: instructions)
        session = fresh
        return fresh
    }

    private func takeSession() -> LanguageModelSession? {
        defer { session = nil }
        return session
    }

    /// The task description plus the catalog's body part and equipment vocabulary, read from the store's labels.
    static func instructions(for store: ExerciseStore) -> String {
        let labels = store.catalog.labels
        let exercises = store.all(includeRetired: true)
        let bodyParts = ExerciseFilter.bodyParts(in: exercises, labels: labels)
            .map { ExerciseFilter.bodyPartLabel($0, labels: labels) }
        let equipment = ExerciseFilter.categories(in: exercises, labels: labels)
            .map { ExerciseFilter.equipmentLabel($0, labels: labels) }
        return """
            You turn a short request typed into a workout app's exercise search field into search filters. \
            Fill only what the request says; leave a list empty when the request does not mention it. \
            Use values exactly as written in these lists, never anything else.
            Body parts: \(bodyParts.joined(separator: ", "))
            Equipment: \(equipment.joined(separator: ", "))
            Muscles map to a body part, for example rear delts and lateral raises are Shoulders, quads and calves are Legs, \
            lats are Back, pecs are Chest.
            """
    }
}

/// Environment access, so a preview or test can inject a stub. Defaults to the launch-time choice.
extension EnvironmentValues {
    @Entry var exerciseQueryParser: any ExerciseQueryParsing = ExerciseQueryParsers.shared
}

enum ExerciseQueryParsers {
    /// The real parser, or under DEBUG with `-stubQueryParser` the stub.
    static let shared: any ExerciseQueryParsing = {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-stubQueryParser") { return StubExerciseQueryParser() }
        #endif
        return ExerciseQueryParser()
    }()
}

#if DEBUG
    /// Deterministic parser for previews and UI tests. "chest with dumbbells" gives Chest plus Dumbbell; any other
    /// sentence gives Legs, so a test can tell a stubbed result from a plain search.
    struct StubExerciseQueryParser: ExerciseQueryParsing {
        func prewarm(store: ExerciseStore) {}

        func parse(_ text: String) async -> ExerciseQuery? {
            let lowered = text.lowercased()
            guard lowered.contains("chest") else { return ExerciseQuery(bodyParts: ["legs"]) }
            return ExerciseQuery(
                bodyParts: ["chest"],
                equipment: lowered.contains("dumbbell") ? ["dumbbell"] : []
            )
        }
    }
#endif

/// A parsed result for the exact text it was parsed from; stale once the text changes.
struct NaturalSearchMatch: Equatable {
    let text: String
    let query: ExerciseQuery
}

extension View {
    /// Natural-language fallback for a `.searchable` field (PLAN 4.6). Prewarms the parser when the view appears; after the
    /// text settles for 400 ms, and only when the plain all-words search finds nothing, asks the parser and stores the
    /// result in `match`. Every other state leaves `match` nil, so the field behaves as plain search.
    func naturalLanguageSearch(
        text: String,
        includeRetired: Bool = false,
        match: Binding<NaturalSearchMatch?>
    ) -> some View {
        modifier(NaturalLanguageSearch(text: text, includeRetired: includeRetired, match: match))
    }
}

private struct NaturalLanguageSearch: ViewModifier {
    let text: String
    let includeRetired: Bool
    @Binding var match: NaturalSearchMatch?
    @Environment(ExerciseStore.self) private var store
    @Environment(\.exerciseQueryParser) private var parser

    func body(content: Content) -> some View {
        content
            .task { parser.prewarm(store: store) }
            .task(id: text) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, store.search(text, includeRetired: includeRetired).isEmpty else { return }
                let parsed = await parser.parse(trimmed)
                guard !Task.isCancelled else { return }
                match = parsed.map { NaturalSearchMatch(text: text, query: $0) }
            }
    }
}
