//
//  DataTransfer.swift
//  Workouts
//

import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers
import WorkoutsKit

/// The Settings Import / Export work around the kit's `WorkoutsJSON` codec. File reading, decoding, encoding and writing
/// run off the main actor; applying and reading the store stay on it, because the `@Model` classes are `MainActor`
/// (the project's default isolation) and so are `Importer` and `Exporter`.
nonisolated enum DataTransfer {
    /// Reads and decodes the picked file. Holds the security-scoped access the file picker grants while it reads.
    @concurrent
    static func readDocument(at url: URL) async throws -> WorkoutsJSON {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try WorkoutsJSON.decode(try Data(contentsOf: url))
    }

    /// Applies a decoded file with ``Importer`` (idempotent by id: importing the same file again changes nothing).
    @MainActor
    static func apply(_ document: WorkoutsJSON, to context: ModelContext, catalog: LibraryCatalog?) throws
        -> ImportReport
    {
        try Importer.apply(document, to: context, catalog: catalog)
    }

    /// A message for a failed import that a person can act on.
    static func message(for error: Error) -> String {
        switch error {
        case is DecodingError:
            "This is not a Workouts export file, or it is damaged."
        default:
            error.localizedDescription
        }
    }

    /// The whole store as a document, read on the main actor.
    @MainActor
    static func exportDocument(container: ModelContainer, catalog: LibraryCatalog?, now: Date) throws -> WorkoutsJSON {
        try Exporter.document(from: container.mainContext, catalog: catalog, exportedAt: now)
    }

    /// Writes the whole store as JSON to a new file named `workouts-export-YYYY-MM-DD.json` in a fresh temporary folder.
    @concurrent
    static func writeExport(container: ModelContainer, catalog: LibraryCatalog?, now: Date = Date()) async throws -> URL
    {
        let document = try await exportDocument(container: container, catalog: catalog, now: now)
        let data = try document.encoded()
        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: WorkoutsJSON.exportFileName(for: now), directoryHint: .notDirectory)
        try data.write(to: file, options: .atomic)
        return file
    }
}

/// What `ShareLink` shares for Export…: the JSON file is only built when a share target is chosen, so opening the sheet
/// is instant and the export reads the store as it is at that moment.
nonisolated struct ExportArchive: Transferable, Sendable {
    let container: ModelContainer
    let catalog: LibraryCatalog?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { archive in
            SentTransferredFile(
                try await DataTransfer.writeExport(container: archive.container, catalog: archive.catalog)
            )
        }
    }
}
