import SwiftData
import Testing

@testable import WorkoutsKit

/// Models that break the CloudKit rules, used only to prove the checker notices.
@Model private final class BadParent {
    @Attribute(.unique) var key: String
    var name: String
    @Relationship(deleteRule: .deny, inverse: \BadChild.parent) var kids: [BadChild] = []
    init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

@Model private final class BadChild {
    var parent: BadParent
    var orphan: BadParent?
    init(parent: BadParent) { self.parent = parent }
}

/// CLAUDE.md: the SwiftData schema must stay CloudKit-compatible (optional relationships, default values, no unique
/// attributes), but SwiftData only complains when the CloudKit container loads. This walks the schema so a violation
/// fails `./dev kit` instead.
@Suite struct CloudKitSchemaRulesTests {
    /// Every CloudKit rule violation in `schema`, each naming `Entity.property`.
    private func problems(in schema: Schema) -> [String] {
        var problems: [String] = []
        for entity in schema.entities {
            if !entity.uniquenessConstraints.isEmpty {
                problems.append("\(entity.name): uniqueness constraint")
            }
            for attribute in entity.attributes {
                let name = "\(entity.name).\(attribute.name)"
                if attribute.isUnique { problems.append("\(name): unique attribute") }
                if !attribute.isOptional && attribute.defaultValue == nil {
                    problems.append("\(name): non-optional without a default value")
                }
            }
            for relationship in entity.relationships {
                let name = "\(entity.name).\(relationship.name)"
                if !relationship.isOptional { problems.append("\(name): non-optional relationship") }
                if relationship.inverseName == nil && relationship.inverseKeyPath == nil {
                    problems.append("\(name): no inverse")
                }
                if relationship.deleteRule == .deny { problems.append("\(name): .deny delete rule") }
            }
        }
        return problems
    }

    @Test func schemaFollowsCloudKitRules() {
        let found = problems(in: Schema(versionedSchema: SchemaV1.self))
        #expect(found.isEmpty, "\(found)")
    }

    @Test func checkerCatchesViolations() {
        let found = problems(in: Schema([BadParent.self, BadChild.self]))
        #expect(found.contains("BadParent.key: unique attribute"))
        #expect(found.contains("BadParent.name: non-optional without a default value"))
        #expect(found.contains("BadParent.kids: .deny delete rule"))
        #expect(found.contains("BadChild.parent: non-optional relationship"))
        #expect(found.contains("BadChild.orphan: no inverse"))
    }
}
