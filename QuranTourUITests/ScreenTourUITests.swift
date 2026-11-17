import XCTest

/// Walks every screen outside the core listening path and photographs it, in light
/// and in dark. It asserts only that each screen can be reached; the screenshots
/// (written to `SHOTS_DIR`, as in `QuranTourUITests`) are for reading by eye.
final class ScreenTourUITests: XCTestCase {
    private let app = XCUIApplication()
    private var prefix = ""

    override func setUp() {
        continueAfterFailure = true
        // System alerts (notifications, location) are answered "Allow".
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for title in ["Allow", "Allow While Using App", "Allow Once", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    private func launch(scheme: String, onboarded: Bool = true, extra: [String] = []) {
        prefix = scheme == "dark" ? "d-" : "l-"
        app.launchArguments = ["-didOnboard", onboarded ? "YES" : "NO", "-colorSchemePreference", scheme] + extra
        app.launch()
    }

    // MARK: - Tours

    func testToolsLight() { launch(scheme: "light"); tools() }
    func testToolsDark() { launch(scheme: "dark"); tools() }
    func testReaderLight() { launch(scheme: "light"); reader() }
    func testReaderDark() { launch(scheme: "dark"); reader() }
    func testSettingsLight() { launch(scheme: "light"); settings() }
    func testSettingsDark() { launch(scheme: "dark"); settings() }

    func testOnboarding() {
        launch(scheme: "light", onboarded: false)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        shot("onboarding-1")
        app.buttons["Continue"].tap()
        sleep(1)
        shot("onboarding-2")
        app.buttons["Continue"].tap()
        sleep(1)
        shot("onboarding-3")
        XCTAssertTrue(app.buttons["Get Started"].exists)
    }

    /// Everything under More except Settings.
    private func tools() {
        sleep(2)
        shot("today")
        app.tabBars.buttons["More"].tap()
        shot("more")

        open("Prayer Times")
        sleep(3)
        shot("prayer")
        if app.buttons["Next day"].waitForExistence(timeout: 3) {
            app.buttons["Next day"].tap()
            sleep(2)
            shot("prayer-tomorrow")
        }
        if app.buttons["Notifications"].exists {
            app.buttons["Notifications"].tap()
            sleep(1)
            let toggle = app.switches.firstMatch
            if toggle.waitForExistence(timeout: 3), (toggle.value as? String) == "0" {
                toggle.tap()
                sleep(2)
                app.tap()  // lets the interruption monitor answer the permission alert
                sleep(1)
            }
            shot("prayer-notifications")
            back()
        }
        back()

        open("Qibla")
        sleep(2)
        shot("qibla")
        back()

        open("Islamic Calendar")
        sleep(1)
        shot("calendar")
        if app.buttons["Next"].exists {
            app.buttons["Next"].tap()
            sleep(1)
            shot("calendar-next")
        }
        back()

        open("Bookmarks")
        shot("bookmarks")
        back()

        open("Dhikr")
        let counter = app.buttons.matching(NSPredicate(format: "label CONTAINS ' of '")).firstMatch
        if counter.waitForExistence(timeout: 3) {
            for _ in 0..<3 { counter.tap() }
        }
        shot("dhikr")
        if app.buttons["Set goal"].exists {
            app.buttons["Set goal"].tap()
            sleep(1)
            shot("dhikr-goal")
            app.buttons["Cancel"].tap()
        }
        back()

        open("99 Names")
        sleep(1)
        shot("names")
        if app.buttons["Flashcards"].exists {
            app.buttons["Flashcards"].tap()
            sleep(1)
            shot("names-flashcards")
            app.buttons["Done"].tap()
        }
        back()
    }

    /// The reader's sheets: ayah actions, word by word with word repeat, tafsir,
    /// reading type, the options menu and a surah download.
    private func reader() {
        app.tabBars.buttons["Quran"].tap()
        XCTAssertTrue(app.buttons["Play Al-Faatiha"].waitForExistence(timeout: 5))
        shot("list")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'The Opening'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Ayah 2"].waitForExistence(timeout: 5))
        shot("reader")

        app.buttons["Ayah 2"].tap()
        XCTAssertTrue(app.buttons["Word by word"].waitForExistence(timeout: 5))
        shot("ayah-actions")
        if app.buttons["Bookmark"].exists { app.buttons["Bookmark"].tap() }

        app.buttons["Word by word"].tap()
        let repeatWords = app.buttons["Repeat words"]
        if repeatWords.waitForExistence(timeout: 15) {
            shot("words")
            repeatWords.tap()
            let chips = app.scrollViews.buttons.matching(NSPredicate(format: "label CONTAINS ','"))
            if chips.count >= 2 {
                chips.element(boundBy: 0).tap()
                shot("words-picking")
                chips.element(boundBy: 1).tap()
                sleep(4)
                shot("words-repeating")
                let stop = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stop repeating'")).firstMatch
                XCTAssertTrue(stop.exists, "Word repeat never started")
                if stop.exists { stop.tap() }
            } else {
                XCTFail("Found \(chips.count) word chips")
            }
        } else {
            shot("words-failed")
            XCTFail("Word by word never loaded")
        }
        back()

        app.buttons["Tafsir"].tap()
        sleep(5)
        shot("tafsir")
        back()
        // Back at its small size, the sheet closes with a tap on the page above it.
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Word by word"].exists, "The ayah sheet is still up")
        shot("reader-bookmarked")

        app.buttons["Reading type"].tap()
        sleep(1)
        shot("reading-type")
        if app.buttons["Done"].waitForExistence(timeout: 3) { app.buttons["Done"].tap() }

        app.buttons["Reader options"].tap()
        sleep(1)
        shot("reader-options")
        if app.buttons["Download audio"].exists {
            app.buttons["Download audio"].tap()
            sleep(8)
        } else {
            app.buttons["Next surah"].tap()
        }
        back()
        shot("list-after-download")
        XCTAssertTrue(app.images["Downloaded"].firstMatch.waitForExistence(timeout: 20), "No surah shows as downloaded")

        app.tabBars.buttons["More"].tap()
        open("Bookmarks")
        shot("bookmarks-one")
    }

    private func settings() {
        app.tabBars.buttons["More"].tap()
        open("Settings")
        sleep(1)
        shot("settings-1")
        app.swipeUp()
        shot("settings-2")
        app.swipeUp()
        shot("settings-3")
        app.swipeUp()
        shot("settings-4")
    }

    /// Picks another translation and checks the reader shows it.
    func testTranslationDownload() {
        launch(scheme: "light")
        app.tabBars.buttons["More"].tap()
        open("Settings")
        let edition = app.buttons["Edition"]
        if !edition.waitForExistence(timeout: 3) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(edition.waitForExistence(timeout: 3))
        edition.tap()
        app.buttons["Saheeh International"].tap()
        sleep(1)
        shot("translation-downloading")
        let downloading = app.staticTexts["Downloading for offline reading…"]
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: downloading)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 60), .completed, "Translation never finished downloading")
        XCTAssertFalse(app.alerts.firstMatch.exists, "The translation download failed")
        shot("translation-done")

        app.tabBars.buttons["Quran"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'The Opening'")).firstMatch.tap()
        let ayah = app.buttons["Ayah 2"]
        XCTAssertTrue(ayah.waitForExistence(timeout: 5))
        shot("translation-reader")
        // Saheeh: "[All] praise is [due] to Allah, Lord of the worlds". Pickthall: "Praise be to Allah…"
        XCTAssertTrue((ayah.value as? String ?? "").contains("[All] praise"), "Reader still shows: \(String(describing: ayah.value))")

        // Put the bundled translation back.
        back()
        app.tabBars.buttons["More"].tap()
        app.buttons["Edition"].tap()
        app.buttons["Pickthall"].tap()
    }

    /// Pause after each ayah: with "As long as the ayah", ayah 3 starts about twice
    /// as long after ayah 2 as it does with the pause off.
    func testPauseAfterAyah() {
        launch(scheme: "light")
        app.tabBars.buttons["Quran"].tap()
        XCTAssertTrue(app.buttons["Play Al-Faatiha"].waitForExistence(timeout: 5))
        let nowPlaying = app.buttons["Now Playing"]
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'The Opening'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Ayah 2"].waitForExistence(timeout: 5))

        func secondsFromAyah2ToAyah3() -> TimeInterval {
            app.buttons["Ayah 2"].tap()
            XCTAssertTrue(app.buttons["Word by word"].waitForExistence(timeout: 5))
            // The sheet's Play, not the mini player's behind it.
            app.buttons.matching(NSPredicate(format: "label == 'Play'")).allElementsBoundByIndex.last?.tap()
            wait(for: "Ayah 2 of 7", in: nowPlaying, timeout: 20)
            let start = Date()
            wait(for: "Ayah 3 of 7", in: nowPlaying, timeout: 40)
            let elapsed = Date().timeIntervalSince(start)
            app.buttons["Pause"].firstMatch.tap()
            return elapsed
        }

        playerOption(nowPlaying) {
            // A repeat left on by an earlier run would keep ayah 2 from leading to ayah 3.
            if (nowPlaying.value as? String ?? "").lowercased().contains("repeating") {
                app.buttons["Repeat"].firstMatch.tap()
                app.buttons["Turn off repeat"].tap()
                sleep(1)
            }
            choosePause("Off")
        }
        let plain = secondsFromAyah2ToAyah3()
        playerOption(nowPlaying) {
            choosePause("As long as the ayah")
            shot("now-playing-pause-on")
        }
        let paused = secondsFromAyah2ToAyah3()
        playerOption(nowPlaying) { choosePause("Off") }
        print("TOUR pause-after-ayah: off \(plain)s, on \(paused)s")
        XCTAssertGreaterThan(paused, plain * 1.6, "No pause was left after the ayah (off \(plain)s, on \(paused)s)")
    }

    /// Opens Now Playing, runs `change`, and closes it again.
    private func playerOption(_ nowPlaying: XCUIElement, _ change: () -> Void) {
        nowPlaying.tap()
        XCTAssertTrue(app.buttons["Previous ayah"].waitForExistence(timeout: 5))
        change()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).press(
            forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        sleep(1)
    }

    private func choosePause(_ label: String) {
        app.buttons.matching(NSPredicate(format: "label == 'More'")).allElementsBoundByIndex.last?.tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pause after each ayah'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3))
        app.buttons[label].tap()
        sleep(1)
    }

    // MARK: - Helpers

    private func open(_ row: String) {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No row “\(row)”")
        button.tap()
        sleep(1)
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.exists { button.tap() }
        sleep(1)
    }

    private func wait(for text: String, in element: XCUIElement, timeout: TimeInterval) {
        let done = expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: element)
        if XCTWaiter().wait(for: [done], timeout: timeout) != .completed {
            XCTFail("Status never contained “\(text)”. It was: \(String(describing: element.value))")
        }
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(prefix)\(name).png"))
    }
}
