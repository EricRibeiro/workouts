import CryptoKit
import Foundation

/// Stable ids for library exercises: an RFC 4122 UUIDv5 of `"source:sourceId"` under a pinned namespace.
///
/// `scripts/build-library` duplicates this algorithm and the namespace; the two must stay identical,
/// or ids in `library.json` stop matching ids computed in the app (and in imported history).
public enum LibraryID {
    /// The pinned namespace. Never change it: every stored `exerciseID` for a library exercise derives from it.
    /// F10FF714-3B99-4302-9CBC-74E1768044BE
    public nonisolated static let namespace = UUID(
        uuid: (
            0xF1, 0x0F, 0xF7, 0x14, 0x3B, 0x99, 0x43, 0x02,
            0x9C, 0xBC, 0x74, 0xE1, 0x76, 0x80, 0x44, 0xBE
        )
    )

    /// UUIDv5 (SHA-1) of the name `"<source>:<sourceID>"` in `namespace`.
    public nonisolated static func id(source: String, sourceID: String) -> UUID {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(Data("\(source):\(sourceID)".utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }
}
