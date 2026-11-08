import XCTest

/// The Exercises tab's detail hero (`ExerciseMediaHeader`): a column-wide 16:9 card in every pose, split column included.
final class ExerciseHeroUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExerciseDetailHeroIsAColumnWide16By9Card() throws {
        let app = XCUIApplication.launchedForTesting(["-seedSampleData"])
        let any = app.descendants(matching: .any)

        let tab = any["tab.exercises"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "no Exercises tab")
        tab.tap()
        XCTAssertTrue(any["screen.exercises"].waitForExistence(timeout: 10), "the Exercises list did not open")

        let row = any.matching(NSPredicate(format: "identifier BEGINSWITH 'exercises.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no exercise rows")
        row.tap()

        let hero = any["exerciseDetail.frames"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "the detail hero did not appear")
        let frame = hero.frame
        let detail = any["screen.exerciseDetail"].firstMatch
        XCTAssertTrue(detail.exists, "no detail screen")
        let detailFrame = detail.frame
        let window = app.windows.firstMatch.frame
        print("hero frame \(frame) detail frame \(detailFrame) window \(window)")

        XCTAssertLessThan(abs(frame.width / frame.height - 16.0 / 9.0), 0.05, "hero is not 16:9: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.width, 150, "hero collapsed: \(frame)")
        if frame.minX > 100 || detailFrame.width < window.width {
            XCTAssertGreaterThanOrEqual(
                frame.width,
                detailFrame.width - 48,
                "hero is narrower than its column (\(detailFrame.width) pt): \(frame)"
            )
        }

        for id in ["exerciseDetail.name", "exerciseDetail.segment"] {
            let element = any[id].firstMatch
            XCTAssertTrue(element.exists, id)
            XCTAssertTrue(element.isHittable, "\(id) is not hittable")
        }
    }
}
