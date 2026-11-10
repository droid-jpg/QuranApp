# Quran App: codebase map (audit input)

Generated 2026-11-09 by a read-only Haiku pass. Key loop claims were spot-checked by hand. Paths are under `Quran App/` unless noted.

## 1. Navigation
- **Root:** `Quran_AppApp.swift` TabView with three tabs, **Today / Qur'an / More**, and a custom `EditorialTabBar`. Onboarding is a fullScreenCover.
- **Today** (`Views/HomeView.swift`): verse of the day, quick-start rail (VOTD, last loop, Juz 30), resume card, memorization drills, prayer card, calendar link. Pushes `SurahPageView`. Has its own `HomeMiniPlayer`.
- **Qur'an** (`Views/SurahListView.swift`): surah list with search and filters. The Juz browser is a sheet. Tapping a row opens the reader. A context menu has "Play Audio".
- **More** (`Views/MoreView.swift`): Memorization hub, Qibla, Dhikr, Bookmarks, 99 Names, Calendar, Settings.
- **Reader** (`Views/SurahDetailView.swift`, 1038 lines, `SurahPageView`): pager. Shows the mini `QuranPlayerBar` and a custom overlay `QuranExpandedPlayer`. Sheets: ReadingType, Mushaf, **LoopSettings ("Repeat")**, MemorizeSurah, **WordLoopPicker**, Tafsir. Review is a fullScreenCover.
- **No app-wide mini player.** The player shows only in the reader and on Today.

## 2. Ways to start playback (all go through `AudioService`)
Today: VOTD card, quick-start rail (VOTD, last loop, Juz 30), resume card, memorization drills (Listen/Repeat/Chain). Surah list: long-press, then "Play Audio" (hidden; tapping a row only opens the reader). Reader: header Play, row "Play from here", row "Repeat this ayah", Repeat-sheet presets, "Word by word" loop. Expanded player: drill buttons. CarPlay: Memorized and Juz lists. Siri "Continue Memorizing". Widgets are display-only, with no play intent.
**Fastest path from a cold launch to a chosen surah:** Qur'an tab → find the surah → open the reader → Play (3+ taps, plus scrolling or search).

## 3. Loop and repeat concepts (the core confusion)
State: `LoopSettings` = mode (off/single/segment), start/end ayah, repeatCount (0 = ∞), listenAndRepeat ("Pause to repeat"), gap delay.

| # | Where | UI strings | Behaviour |
|---|---|---|---|
| a | Reader top-bar **"Repeat"** sheet | Presets *Listen / Repeat / Chain* (start immediately). Custom: *Off / This ayah / Range*, Ayah stepper, "Select Ayahs", Times ∞,1,2,3,5,7,10×, "Pause to repeat", gap | Apply only writes state and does **not** restart playback |
| b | Mini-bar loop button | cycles Off → This ayah → Range | scope only |
| c | Expanded player | drills *Listen / Repeat / Chain*, scope segment, Reps ∞,3,5×, "Loop range" From/To | second full loop UI |
| d | Row "Word by word" | "Word Loop – Ayah N", tap first and last word | separate AVPlayer; ignores count, pause and range |
| e | Row "Repeat this ayah" | – | single, ∞ |
| f | Today drills | Listen / Repeat / Chain | chain = working ayah −2 … working |
| g | CarPlay and lock-screen repeat | system | single, ∞ |

**Verified conflicts**
- **Two copies of loop state.** `SurahDetailViewModel.loopSettings` is passed into `play()` (`ViewModels/SurahDetailViewModel.swift:112-123`), so a stale reader copy overrides a loop set from Today, CarPlay, the lock screen or the expanded player. The Repeat sheet also opens from the stale copy.
- Reps control is visible when scope is Off, but the engine ignores it there.
- Word loop overrides the loop without clearing it. The Repeat button state and the summary don't reflect it.
- Chain starts from ayah 1 in the player and sheet, but from working−2 on Today and in Siri.
- Repeat-count options differ: sheet ∞/1/2/3/5/7/10 vs player ∞/3/5. "1×" means play once, not repeat once.
- "Repeat" means four things: the top-bar button, mode "This ayah", the drill, and the row action.
- The loop summary text is written three times with different wording (`QuranPlayerView:78`, `HomeListeningCards:208`, `ListeningSessionStore:31`).

## 4. Player
`AudioService` (EnvironmentObject): isPlaying, currentAyah/Surah, isWordLooping, playbackRate, loopSettings. AVQueuePlayer for ayah files, plus a separate AVPlayer for word loops. Pause-to-repeat gap applies in every mode. Short clips in review and word taps use `ClipPlayer` and `GapClipPlayer`.

## 5. Settings
Appearance (system/light/dark, 7 colour themes) · Reading type sheet, reading faces · Translation language and edition · Reciter · Memorization card display, fill-in-the-blank hint, daily reminder and time · Prayer method and Asr · Prayer notifications (enable, Live Activity, 7 per-prayer toggles, pre-prayer reminder) · About.

## 6. Design system
`DesignSystem.swift` (brand colours, Eyebrow, MetaText, Hairline, DiamondRule, EditorialSection, OutlineButton/Chip, PlayCircle, BarButton 44 pt, …), `AppTheme.swift` (7 palettes), `ReadingTypography.swift`, `EditorialControls.swift`, `AnimationKit.swift`. **No spacing tokens:** spacing values are literals everywhere.

## 7. Features
Reader (Arabic, translation, word-by-word, tafsir, Mushaf, bookmarks, offline download, resume) · audio with word timings, prefetch, Now Playing · surah list, juz browser, search · memorization (spaced repetition, goals, review with fill-in-the-blank, guide, reminder, Siri) · prayer times, notifications, Live Activity · Qibla · Dhikr · 99 Names with flashcards · Islamic calendar · verse of the day · streaks · CarPlay · widgets · iCloud sync · onboarding.

## 8. Smells
`SurahDetailView.swift` 1038 lines · unused `SectionHeader`, `GoalBadge`, and the `QuranWidgetControl` placeholder · `MemorizationView.swift` defines no MemorizationView · ClipPlayer vs GapClipPlayer duplicated · PlayerScope vs LoopSettings.Mode duplicated · three drill-button sets · chain-start logic in three places · debug print in `PrayerLiveActivityService:75` · `build/` folder inside the project tree.
