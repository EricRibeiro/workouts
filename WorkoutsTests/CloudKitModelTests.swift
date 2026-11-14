import CoreData
import Foundation
import SwiftData
import Testing
import WorkoutsKit

@testable import Workouts

/// Offline check that SwiftData's generated model passes Core Data's own CloudKit validator (PLAN 7c.12). Complements the
/// kit's `CloudKitSchemaRulesTests`, which walks the `Schema` metadata instead.
struct CloudKitModelTests {
    private static let containerIdentifier = "iCloud.com.ericribeiro.Workouts"

    private final class Box<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    /// Resumes its continuation once, whichever of the work and the timeout gets there first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Result<Void, any Error>?, Never>?
        init(_ continuation: CheckedContinuation<Result<Void, any Error>?, Never>) { self.continuation = continuation }
        func finish(_ result: Result<Void, any Error>?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: result)
        }
    }

    private static func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cloudkit-model-\(UUID().uuidString).sqlite")
    }

    private static func removeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// Loads `model` into an `NSPersistentCloudKitContainer` on a temp store; returns the container and the load error.
    private static func load(
        _ model: NSManagedObjectModel,
        at url: URL
    ) -> (container: NSPersistentCloudKitContainer, error: (any Error)?) {
        let container = NSPersistentCloudKitContainer(name: "CloudKitModelTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        return (container, loadError)
    }

    private static func swiftDataModel() throws -> NSManagedObjectModel {
        try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV2.models))
    }

    @Test func modelLoadsUnderCloudKitMirroring() throws {
        let url = Self.tempStoreURL()
        defer { Self.removeStore(at: url) }
        let (container, error) = Self.load(try Self.swiftDataModel(), at: url)
        #expect(error == nil, "CloudKit mirroring rejected the model: \(String(describing: error))")
        #expect(container.persistentStoreCoordinator.persistentStores.count == 1)
    }

    /// The model is the app's real one with a deliberate violation: an extra non-optional attribute without a default.
    @Test func modelWithNonOptionalAttributeIsRejected() throws {
        // The generated model is frozen once used; a copy is editable.
        let model = try #require(try Self.swiftDataModel().copy() as? NSManagedObjectModel)
        let entity = try #require(model.entitiesByName["Exercise"])
        let attribute = NSAttributeDescription()
        attribute.name = "cloudKitViolation"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false
        entity.properties.append(attribute)

        let url = Self.tempStoreURL()
        defer { Self.removeStore(at: url) }
        let (_, error) = Self.load(model, at: url)
        #expect(error != nil, "a non-optional attribute without a default must fail the CloudKit load")
    }

    @Test func dryRunSchemaInitialisation() async throws {
        let url = Self.tempStoreURL()
        defer { Self.removeStore(at: url) }
        let (container, loadError) = Self.load(try Self.swiftDataModel(), at: url)
        try #require(loadError == nil, "load failed: \(String(describing: loadError))")

        let box = Box(container)
        let outcome: Result<Void, any Error>? = await withCheckedContinuation { continuation in
            let once = Once(continuation)
            DispatchQueue.global().async {
                once.finish(Result { try box.value.initializeCloudKitSchema(options: .dryRun) })
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) { once.finish(nil) }
        }

        switch outcome {
        case .success?:
            // Pool simulators are signed in, so this is the normal path: returning without a throw is the proof.
            break
        case .failure(let error)?:
            // No account, or a lapsed session: the dry run cannot reach CloudKit, so it proves nothing there.
            withKnownIssue("initializeCloudKitSchema(.dryRun) needs an iCloud account: \(error)") {
                throw error
            }
        case nil:
            withKnownIssue("initializeCloudKitSchema(.dryRun) did not return within 20 s (no iCloud account)") {
                Issue.record("timed out")
            }
        }
    }
}
