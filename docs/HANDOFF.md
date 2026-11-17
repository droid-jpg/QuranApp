# Quran app rebuild: handoff

Paste this into a new chat to continue. Written 2026-11-16.

## Where the work is

- Repo: `droid-jpg/QuranApp`, branch **`rebuild/light`**, checked out at `~/Projects/QuranApp` (not the iCloud Desktop copy, where git is very slow).
- Build: `xcode-select` points at the command-line tools, so prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Scheme `Quran App`, simulator iPhone 17 (iOS 26).
- Smoke test: scheme `QuranTour` (`QuranTourUITests/QuranTourUITests.swift`) launches, plays Al-Faatiha, taps ayahs 2 and 4 to repeat. Set `TEST_RUNNER_SHOTS_DIR=<folder>` to get screenshots. It passes.
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

Audio comes from `verses.quran.com/<reciter>/mp3/SSSAAA.mp3`; timings from `api.quran.com/api/v4/recitations/<id>/by_chapter/<n>?fields=segments`.

## Checked

Builds. In the simulator: launch, play a surah from the list, tap two ayahs to repeat, word highlight, Now Playing.

## Not done or not checked

1. Motion and haptics pass (springs, transitions). Only basic haptics and the mini player zoom exist.
2. Not run at all: Settings, Prayer Times, Qibla, Dhikr, 99 Names, Calendar, Bookmarks, onboarding, the widget, dark mode, a real device, real audio output, offline behaviour, lock-screen controls, pause after each ayah, word repeat, translation download, surah download.
3. Now Playing looked partly see-through at the top in one screenshot; check whether that was mid-transition.
4. Settings has a saved-audio readout and translation download that were written but never exercised.
5. Leftovers to delete: `MemorizationStatusCard`, `StatDot`, `TintedCardModifier` in `DesignSystem.swift` if unused; the README and screenshots still describe the old app.
6. History: `main` on GitHub was rewritten to remove the Asad translation from the bundled text, but this branch (like the older `fix/` branches) is based on the old history that still contains it. The branch's current tree bundles Pickthall. Landing on `main` cleanly needs the final tree committed on top of `origin/main` rather than a merge.
7. The seven colour themes were kept: they turned out to be accent colours, not backgrounds, so there was nothing heavy to remove.
8. Tapping a word to hear it moved from the reader into Word by word.
