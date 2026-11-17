import XCTest

/// A smoke test of the core path: launch, play a surah, tap two ayahs to repeat.
/// Screenshots go to the folder in `SHOTS_DIR` (a host path; the simulator shares
/// the Mac's file system).
final class QuranTourUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-didOnboard", "YES"]
        app.launch()
    }

    func testPlayAndRepeat() {
        shot("01-today")

        app.tabBars.buttons["Quran"].tap()
        XCTAssertTrue(app.buttons["Play Al-Faatiha"].waitForExistence(timeout: 5))
        shot("02-list")

        app.buttons["Play Al-Faatiha"].tap()
        let nowPlaying = app.buttons["Now Playing"]
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 5))
        waitForStatus(containing: "Ayah", in: nowPlaying)
        shot("03-playing")

        // Open the reader from the row, then choose ayahs 2 to 4.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'The Opening'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Repeat"].waitForExistence(timeout: 5))
        shot("04-reader")
        app.buttons["Repeat"].tap()
        shot("05-picking")
        app.buttons["Ayah 2"].tap()
        app.buttons["Ayah 4"].tap()
        waitForStatus(containing: "repeating 2–4", in: nowPlaying)
        shot("06-repeating")

        nowPlaying.tap()
        sleep(2)
        shot("07-now-playing")
    }

    private func waitForStatus(containing text: String, in element: XCUIElement, timeout: TimeInterval = 20) {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let done = expectation(for: predicate, evaluatedWith: element)
        if XCTWaiter().wait(for: [done], timeout: timeout) != .completed {
            XCTFail("Status never contained “\(text)”. It was: \(String(describing: element.value))")
        }
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
