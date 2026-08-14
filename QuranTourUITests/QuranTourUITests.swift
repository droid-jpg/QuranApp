import XCTest

/// A scripted walk through the app the way someone would actually use it:
/// onboarding, the dashboard, prayer times, the surah list, a reader session
/// with audio, and each screen behind More. Nothing here asserts a design — it
/// drives the UI and photographs every step so the screens can be reviewed.
///
/// Every step is defensive on purpose: a missing element logs and moves on
/// rather than ending the tour, so one broken screen doesn't hide the rest.
final class QuranTourUITests: XCTestCase {

    var app: XCUIApplication!
    private var shotIndex = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-UITour", "1"]
        app.launch()
    }

    // MARK: - Plumbing

    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Screenshot to the runner's Documents folder, which the host can read
    /// straight off disk — no xcresult digging.
    private func snap(_ name: String) {
        shotIndex += 1
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let file = String(format: "%02d-%@.png", shotIndex, name)
        try? data.write(to: docs.appendingPathComponent(file))
        log("SHOT \(file)")
    }

    /// Write the accessibility tree so the next run can drive by label rather
    /// than by guesswork — and so gaps in it show up as gaps in VoiceOver.
    private func dump(_ name: String) {
        let tree = app.debugDescription
        try? tree.write(to: docs.appendingPathComponent("tree-\(name).txt"),
                        atomically: true, encoding: .utf8)
        log("TREE tree-\(name).txt (\(tree.count) chars)")
    }

    private func log(_ message: String) {
        print("TOUR ▸ \(message)")
    }

    private func pause(_ seconds: TimeInterval = 0.9) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Tap the first element matching `label` among buttons and texts.
    @discardableResult
    private func tap(_ label: String, timeout: TimeInterval = 3) -> Bool {
        for query in [app.buttons, app.staticTexts, app.otherElements, app.images] {
            let element = query[label]
            if element.waitForExistence(timeout: timeout), element.isHittable {
                element.tap()
                log("tapped \(label)")
                pause()
                return true
            }
        }
        // Fall back to a label-prefix match — SwiftUI often combines children
        // into one element whose label is the whole row.
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", label)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch
        if element.waitForExistence(timeout: 1), element.isHittable {
            element.tap()
            log("tapped (prefix) \(label)")
            pause()
            return true
        }
        log("MISSING \(label)")
        return false
    }

    /// Tap a point given in normalized screen coordinates.
    private func tapAt(_ x: CGFloat, _ y: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        pause()
    }

    private func pressAt(_ x: CGFloat, _ y: CGFloat, seconds: TimeInterval = 0.8) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).press(forDuration: seconds)
        pause()
    }

    private func swipeUp()   { app.swipeUp(velocity: .slow);   pause(0.6) }
    private func swipeDown() { app.swipeDown(velocity: .slow); pause(0.6) }

    /// Dismiss whatever system alert is up (notifications, location).
    private func clearSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Allow While Using App", "OK", "Continue"] {
            let button = springboard.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                log("system alert: \(label)")
                pause()
            }
        }
    }

    /// The app's own tab bar (three letterspaced labels along the bottom edge).
    private func openTab(_ name: String) {
        let tab = app.buttons[name]
        if tab.waitForExistence(timeout: 2), tab.isHittable {
            tab.tap()
        } else {
            let x: CGFloat = name == "Today" ? 0.17 : (name == "Quran" ? 0.5 : 0.83)
            tapAt(x, 0.955)
        }
        pause(1.0)
        log("tab → \(name)")
    }

    // MARK: - The tour

    /// A quick pass that photographs and dumps the three tabs, so the detailed
    /// flows can be written against the real element labels.
    func testExplore() throws {
        pause(3.0)
        // Onboarding may still be up on a fresh container.
        for label in ["Continue", "Get Started", "Begin"] {
            var guard_ = 0
            while app.buttons[label].exists && app.buttons[label].isHittable && guard_ < 6 {
                app.buttons[label].tap(); pause(0.7); guard_ += 1
            }
        }
        clearSystemAlerts()
        pause(1.5)
        snap("explore-home"); dump("home")

        tapAt(0.5, 0.945);  pause(1.5)
        snap("explore-quran"); dump("quran")

        tapAt(0.83, 0.945); pause(1.5)
        snap("explore-more"); dump("more")

        tapAt(0.17, 0.945); pause(1.0)
        log("explore done")
    }

    // MARK: - Flows

    /// Tap the first element whose label starts with `prefix`.
    @discardableResult
    private func tapPrefix(_ prefix: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", prefix)
        let element = app.buttons.matching(predicate).firstMatch
        if element.waitForExistence(timeout: timeout), element.isHittable {
            element.tap(); log("tapped \(prefix)"); pause(1.0); return true
        }
        let any = app.descendants(matching: .any).matching(predicate).firstMatch
        if any.waitForExistence(timeout: 0.5), any.isHittable {
            any.tap(); log("tapped (any) \(prefix)"); pause(1.0); return true
        }
        log("MISSING \(prefix)")
        return false
    }

    private func exists(_ prefix: String) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", prefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch.exists
    }

    private func openTabButton(_ name: String) {
        let tab = app.buttons[name]
        if tab.waitForExistence(timeout: 3) { tab.tap() } else { tapAt(0.5, 0.93) }
        pause(1.2)
    }

    private func settle() { pause(2.5) }

    // MARK: 1 — Home

    func testHome() throws {
        settle(); settle()
        snap("home"); dump("home-loaded")

        // Every block of the dashboard.
        for i in 1...4 { swipeUp(); snap("home-scroll-\(i)") }
        dump("home-bottom")
        for _ in 1...6 { swipeDown() }
        pause(0.8)

        // Verse of the day: play it.
        if tapPrefix("Play verse") || tapPrefix("Verse of the day") || tapPrefix("VERSE OF THE DAY") {
            pause(4.0)
            snap("home-verse-playing"); dump("home-playing")
        }

        // Whatever player turned up, work it.
        if exists("Pause") { tapPrefix("Pause"); snap("home-paused") }
        if exists("Play")  { tapPrefix("Play");  snap("home-resumed") }
        pause(3.0)
        snap("home-after-audio"); dump("home-after-audio")

        // Juz 30 quick start
        if tapPrefix("JUZ 30") {
            pause(3.5)
            snap("home-juz30"); dump("home-juz30")
        }
    }

    // MARK: 2 — Qur'an list and reader

    func testReader() throws {
        settle()
        openTabButton("Quran")
        snap("list"); dump("list")

        // Search
        let field = app.textFields["Search surah"]
        if field.waitForExistence(timeout: 3) {
            field.tap(); field.typeText("nas")
            pause(1.2); snap("list-search"); dump("list-search")
            if app.buttons["Clear search"].exists { app.buttons["Clear search"].tap(); pause(0.8) }
        } else { log("MISSING search field") }
        snap("list-search-cleared")

        // Filters
        for f in ["SAVED", "MEMORIZED", "LEARNING", "ALL"] {
            if app.buttons[f].exists { app.buttons[f].tap(); pause(0.8); snap("list-filter-\(f)") }
        }

        // Juz browser
        if app.buttons["Browse by juz"].exists {
            app.buttons["Browse by juz"].tap(); pause(1.5)
            snap("juz"); dump("juz")
            swipeUp(); snap("juz-scrolled")
            if !tapPrefix("Done") { app.swipeDown(velocity: .fast) }
            pause(1.0)
        }

        // Open a short surah with audio worth hearing.
        if !tapPrefix("1, Al-Faatiha") { tapAt(0.5, 0.30) }
        settle()
        snap("reader"); dump("reader")

        swipeUp(); snap("reader-scroll-1")
        swipeUp(); snap("reader-scroll-2"); dump("reader-scrolled")
        swipeDown(); swipeDown(); pause(0.8)

        // Long press an ayah → the editorial menu
        pressAt(0.5, 0.5, seconds: 1.0)
        snap("ayah-menu"); dump("ayah-menu")
        tapAt(0.5, 0.08)
        pause(1.0); snap("ayah-menu-dismissed")

        // Reading type sheet — does a face change repaint the page behind it?
        if app.buttons["Reading type"].exists {
            app.buttons["Reading type"].tap(); settle()
            snap("type-sheet"); dump("type-sheet")
            for face in ["Charter", "Georgia", "Palatino", "Iowan"] where exists(face) {
                tapPrefix(face); break
            }
            snap("type-sheet-changed")
            if !tapPrefix("Done") { tapAt(0.5, 0.02) }
            pause(1.5)
            snap("reader-after-face"); dump("reader-after-face")
        }

        // Repeat sheet
        if app.buttons["Repeat"].exists {
            app.buttons["Repeat"].tap(); settle()
            snap("loop-sheet"); dump("loop-sheet")
            swipeUp(); snap("loop-sheet-scrolled")
            if !tapPrefix("Done") { app.swipeDown(velocity: .fast) }
            pause(1.2)
        }

        // ⋯ panel
        if app.buttons["More"].exists {
            app.buttons["More"].tap(); pause(1.2)
            snap("reader-more"); dump("reader-more")
            tapAt(0.5, 0.08); pause(0.8)
        }

        snap("reader-before-play"); dump("reader-before-play")
    }

    // MARK: 3 — Audio and the player

    func testPlayer() throws {
        settle()
        openTabButton("Quran")
        if !tapPrefix("1, Al-Faatiha") { tapAt(0.5, 0.30) }
        settle()
        dump("player-reader")

        // Play the first ayah from its control strip.
        if !tapPrefix("Play ayah") && !tapPrefix("Play") { tapAt(0.11, 0.62) }
        pause(5.0)
        snap("playing"); dump("playing")

        // Expand the docked player. Time it — this used to be the lag.
        let start = Date()
        tapAt(0.5, 0.915)
        pause(1.5)
        log("expand took \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        snap("player-expanded"); dump("player-expanded")

        for label in ["Next ayah", "Next", "Previous ayah", "Previous"] where app.buttons[label].exists {
            app.buttons[label].tap(); pause(2.5)
            snap("player-\(label.replacingOccurrences(of: " ", with: "-"))")
        }
        dump("player-after-skip")

        // The loop range picker (what replaced A/B)
        for label in ["Set range", "Range", "From", "Loop range"] where exists(label) {
            tapPrefix(label); settle()
            snap("range-picker"); dump("range-picker")
            swipeUp(); snap("range-picker-scrolled")
            if !tapPrefix("Done") { app.swipeDown(velocity: .fast) }
            pause(1.2)
            break
        }
        snap("player-expanded-2"); dump("player-expanded-2")

        // Collapse, then stop.
        app.swipeDown(velocity: .fast); pause(1.2)
        snap("player-collapsed"); dump("player-collapsed")
        for label in ["Stop", "Close player", "Stop playback"] where app.buttons[label].exists {
            app.buttons[label].tap(); pause(1.0); break
        }
        snap("player-stopped")
    }

    // MARK: 4 — Everything behind More

    func testMore() throws {
        settle()
        openTabButton("More")
        snap("more"); dump("more")
        swipeUp(); snap("more-scrolled")
        swipeDown(); pause(0.8)

        let rows = ["Memorization", "Qibla compass", "Dhikr counter",
                    "Bookmarks", "99 Names of Allah", "Islamic calendar", "Settings"]
        for row in rows {
            openTabButton("More")
            pause(0.8)
            // Scroll until the row is on screen.
            var tries = 0
            while !app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch.isHittable && tries < 4 {
                swipeUp(); tries += 1
            }
            guard tapPrefix(row) else { continue }
            settle()
            let slug = row.lowercased().replacingOccurrences(of: " ", with: "-")
            snap("more-\(slug)"); dump("more-\(slug)")
            swipeUp(); snap("more-\(slug)-scrolled")
            dump("more-\(slug)-scrolled")
            swipeDown()
            // Back out: the pushed screens use a system back button.
            if !tapPrefix("Back") {
                let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
                a.press(forDuration: 0.05, thenDragTo: b)
            }
            pause(1.2)
        }
        snap("more-end")
    }
}
