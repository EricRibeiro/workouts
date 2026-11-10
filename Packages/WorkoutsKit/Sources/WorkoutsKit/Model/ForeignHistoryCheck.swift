import Foundation
import OSLog
import SwiftData

/// Reads the SwiftData history since the last call and says whether anything other than this app wrote to the store.
/// The remote-change notification also fires for the app's own saves, so ``RemoteChangeObserver`` asks this before it
/// reloads: a burst whose transactions all carry `localAuthor` (set as `ModelContext.author` on the app's context) is
/// dropped, and one from the CloudKit mirror or another context is not.
public final class ForeignHistoryCheck {
    private let context: ModelContext
    private let localAuthor: String
    private var lastToken: DefaultHistoryToken?

    public init(context: ModelContext, localAuthor: String) {
        self.context = context
        self.localAuthor = localAuthor
    }

    /// Fails open: when the history cannot be read, a spurious reload is the old behaviour.
    public func hasForeignTransactions() -> Bool {
        do {
            var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
            if let last = lastToken {
                descriptor.predicate = #Predicate { $0.token > last }
            }
            let transactions = try context.fetchHistory(descriptor)
            if let newest = transactions.last?.token { lastToken = newest }
            return transactions.contains { $0.author != localAuthor }
        } catch {
            KitLog.engine.error("Could not read the store history: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }
}
