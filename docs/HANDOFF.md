# Quran app rebuild: handoff

Paste this into a new chat to continue. Written 2026-11-16, updated the same night after a second session.

## Where the work is

- Repo: `droid-jpg/QuranApp`, branch **`rebuild/light`**, checked out at `~/Projects/QuranApp` (not the iCloud Desktop copy, where git is very slow).
- Build: `xcode-select` points at the command-line tools, so prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Scheme `Quran App`, simulator iPhone 17 (iOS 26).
- Tests: scheme `QuranTour`. `QuranTourUITests` is the smoke test (launch, play Al-Faatiha, tap ayahs 2 and 4 to repeat). `ScreenTourUITests` walks every other screen in light and dark and checks word repeat, surah download, translation download and the pause after each ayah. Set `TEST_RUNNER_SHOTS_DIR=<folder>` to get screenshots. `.tour.sh [TestClass/testName …]` (untracked) runs them and writes shots to `.shots/tour`; `.build.sh` builds. The simulator needs a location (`xcrun simctl location <id> set 39.04,-77.49`) and `xcrun simctl privacy <id> grant location sami.Quran-App` for the prayer screens.
- The Claude iOS Simulator tool will not attach until the user runs `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## What the user asked for

Lighter engine and a lighter, more delightful feel. Their answers: editorial serif look kept, system gestures only, launch on Today, tap two ayahs to repeat, keep what is played for offline, data reset is fine. Removed on purpose: memorization engine, CarPlay, Live Activity, iCloud sync, streaks, Siri, home-screen widgets. Kept on request: pause after each ayah and word repeat (both tucked away), and the lock-screen prayer time widget.

## How it is built now

| File | Role |
|---|---|
| `Services/Player.swift` | The one audio engine (`@Observable`). Plays one local file per ayah; repeat is a `RepeatRange`; `step(after:)` decides what follows each ayah. |
| `Services/AudioStore.swift` | Fetches an ayah's file to Application Support, then it is played from disk. `Downloads` tracks whole-surah downloads. |
| `Services/WordData.swift` | Word timings and word meanings from quran.com, cached to disk. `WordAlignment` maps bundled words to quran.com word positions. |
| `Services/QuranText.swift` | Bundled Arabic, transliteration and Pickthall; other translations download once. |
| `Services/PrayerTimesService.swift` | A month of times per request, cached; feeds notifications and the widget. |
| `Views/RootView.swift` | `AppRouter`, system tabs, routes, More. Mini player is the tab bar's bottom accessory. |
| `Views/PlayerViews.swift` | Mini player, Now Playing, `RepeatMenu`, `RecitedArabic` (word highlight). |
| `Views/ReaderView.swift` | Reader, `AyahRow` (equatable, one text per ayah), repeat picking. |
| `Views/AyahSheets.swift` | Ayah actions, Word by word (with "Repeat words"), Tafsir. |
| `Views/TodayView.swift`, `Views/QuranListView.swift` | Today; surah list, `SurahRow`, Juz list. |
| `Views/AnimationKit.swift` | Motion tokens (`quick`, `standard`, `spring`, `bouncy`, all springs, all a cross-fade under Reduce Motion), `Motion.pop`, the press styles (`CardButtonStyle`, `RowPressStyle`) and `.arrives(n)`. |
| `Views/Haptics.swift` | The haptic vocabulary: tap, selection, impact, success, warning, error. Generators are kept and re-armed. |

Audio comes from `verses.quran.com/<reciter>/mp3/SSSAAA.mp3`; timings from `api.quran.com/api/v4/recitations/<id>/by_chapter/<n>?fields=segments`.

## Checked

Builds. In the simulator (iPhone 17, iOS 26), by UI test and by reading the screenshots, in light and dark:

- Core path: launch, play a surah from the list, tap two ayahs to repeat, word highlight, Now Playing.
- Onboarding (three pages), Today, More, Prayer Times (today, another day, notifications with the system prompt), Qibla, Islamic Calendar, Bookmarks (empty and with one), Dhikr and its goal sheet, 99 Names and flashcards, Settings top to bottom.
- Reader: ayah actions, bookmark, Word by word, word repeat (starts, shows, stops), Tafsir, Reading type, reader options, surah download (the row shows Downloaded).
- Translation download: choosing Saheeh International downloads it and the reader shows it.
- Pause after each ayah: with "As long as the ayah", ayah 3 started 10.1 s after ayah 2 instead of 5.1 s.
- Settings' saved-audio readout shows a real size.

## Done in the second session

1. Motion and haptics pass. Every state change animates with a spring; presses sink and spring back; Today's blocks settle in one after another; one ayah dissolves into the next in Now Playing, whose ayah is now centred; the play button swells when playing; skip glyphs bounce; a small waveform moves beside the surah being recited; bookmark, repeat marker, download badge and the picking circles pop in. Haptics: tab change, a failed ayah, a finished or failed download, on top of what was there.
2. Onboarding rewritten in the app's own type and controls. It no longer advertises memorization, no longer says "nothing leaves your device" (a rounded location goes to aladhan.com), and its location button turns into "Prayer times are ready".
3. A translation picked in onboarding was never downloaded. The app now fetches the selected translation at launch if it is missing, and an open reader reloads when it arrives.
4. Pause after each ayah, and fetching an ayah, now play silence so iOS does not suspend the app on a locked phone and strand playback. Not yet tried on a device.
5. The ayah sheet shrinks back after Word by word or Tafsir instead of staying full height.
6. A surah whose download did not finish shows a mark in the list (the state existed but was never shown).
7. Deleted: `MemorizationStatusCard`, `StatDot`, `TintedCardModifier`, `PlayCircle`, `BarButton`, `ErrorView`, the unused sliders and a few unused tokens. README rewritten for this version, with new screenshots.
8. Now Playing is opaque. What looked see-through was the dimmed page above the sheet's top edge.

## Not done or not checked

1. A real device: audio output, the haptics, the lock-screen and Control Center controls, background playback (including item 4 above), the Qibla compass heading.
2. Offline behaviour was read in code, not run: the simulator shares the Mac's network.
3. The lock-screen widget builds but was not placed on a lock screen.
4. Reduce Motion and Dynamic Type sizes were not run.
5. History: `main` on GitHub was rewritten to remove the Asad translation from the bundled text, but this branch (like the older `fix/` branches) is based on the old history that still contains it. The branch's current tree bundles Pickthall. Landing on `main` cleanly needs the final tree committed on top of `origin/main` rather than a merge.
6. The second session's changes are in the working tree, not committed.
7. Long surah subtitles truncate in the list ("The Family of Imraan ·…"), so the ayah count is lost on a few rows.
8. `docs/REDESIGN.md` and `docs/audit/` describe the app before the rebuild.
9. The seven colour themes were kept: they are accent colours, not backgrounds. Tapping a word to hear it lives in Word by word.
