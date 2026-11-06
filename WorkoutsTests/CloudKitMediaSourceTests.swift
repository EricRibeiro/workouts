import CloudKit
import Testing

@testable import Workouts

struct CloudKitMediaSourceTests {
    @Test func cellularAllowedFetchesAtUserInitiatedPriority() {
        let configuration = CloudKitMediaSource.operationConfiguration(allowsCellular: true)
        #expect(configuration.allowsCellularAccess == true)
        #expect(configuration.qualityOfService == .userInitiated)
    }

    @Test func wifiOnlyFetchesBlockCellularAndRunAtUtilityPriority() {
        let configuration = CloudKitMediaSource.operationConfiguration(allowsCellular: false)
        #expect(configuration.allowsCellularAccess == false)
        #expect(configuration.qualityOfService == .utility)
    }
}
