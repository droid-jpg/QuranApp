# Quran App: UX audit (input for the redesign)

2026-11-09 · iPhone 17e simulator, iOS 27, light mode, fresh install · source: `QuranTour` UI test (52 screenshots in `shots/`, grouped in `sheets/`) plus the code map in `ARCHITECTURE.md`.
Severity: **P0** blocks or confuses core listening · **P1** clear friction or visual bug · **P2** polish.

## A. Getting to listening (the main complaint)
1. **P0. Today has no way to just listen to a surah.** It offers Verse of the Day, Juz 30, Loop, Memorization and nothing else. The lower ~45% of Today is blank on a fresh install (`01-explore-home`, `02…05-home-scroll`: swiping changes nothing).
2. **P0. Tapping a surah in the list only opens the reader.** Playing needs a second tap on a large play circle under the title. "Play Audio" exists only in a hidden long-press menu. Cold launch → listening to Al-Baqara = tab, search or scroll, row, play: **≥3 taps plus a search**.
3. **P1. No app-wide player.** The mini player exists only in the reader and on Today, so leaving the reader for the list or More loses the controls.
4. **P1. The notification permission prompt appears on first launch** with no context, over Today (`01-home`).
5. **P1. Inconsistent playback state on Today.** The card says "PAUSED" with a *pause* icon. The Verse-of-day row shows a pause icon while paused. The progress bar reads 0:03 / 0:03 (`06-home-verse-playing`).
6. **P1. After Stop, the mini player stays visible with a pause icon** (`07-player-stopped`).

## B. Loop and repeat (the second complaint)
There are **seven entry points and four meanings of "Repeat"** (detail in ARCHITECTURE.md §3):
7. **P0. Two separate full loop UIs**: the reader's top-bar "Repeat" sheet and the expanded player. They differ in options (Times ∞/1/2/3/5/7/10 vs Reps ∞/3/5), labels ("Times" vs "Reps", "Range" vs "Loop range") and semantics (the sheet has Cancel/Apply, but its presets play immediately and Apply does *not* restart playback).
8. **P0. Bug: the loop state can silently revert.** The reader view model keeps its own `loopSettings` and passes it to `play()`, so a loop set from Today, the player, the lock screen or CarPlay gets overwritten the next time an ayah is played from the reader.
9. **P1. Reps can be set while scope is Off**, and the setting does nothing (`02-player-expanded`: ∞ selected with OFF).
10. **P1. "Listen / Repeat / Chain" drills mean different ranges** in different places (Chain = 1…N in the player, N−2…N on Today and in Siri). The drills live in the general player, labelled "MEMORIZE AYAH 2 · 1 TAP · PLAYS NOW", so a casual listener sees memorization jargon.
11. **P1. The status text contradicts itself.** VOTD playback shows "looping ×1" when it plays once. A Range loop is described as "chaining 3–4". The loop summary is written three times with different wording.
12. **P1. Word-by-word loop is a fourth system.** It ignores count, pause and range, and the Repeat indicator doesn't show it.
13. **P2. "Pause to repeat" plus a gap picker** is a third axis that applies to every mode, which makes the mental model harder still.

## C. Density and legibility
14. **P1. Expanded player packs 6 control rows into half a screen** (drills, scrubber, scope + reps, range card, speed, transport), over a dimmed reader. The label "FROM" is truncated to "FR…" (`03-range-picker`).
15. **P1. The ayah long-press menu holds 9 actions** (Play from here, Repeat this ayah, Word by word, Tafsir, Memorize from here, Add to review, Bookmark, Share ×2), and it's the *only* way into Bookmarks, review and tafsir. Empty states have to explain the gesture (`09-more-bookmarks`).
16. **P1. Heavy use of tiny letter-spaced small caps** (≈9–10 pt) for tab labels, eyebrows, chips and segment labels. Translations, transliteration, subtitles and placeholders are grey italics with low contrast. The tab bar is text only, with no icons.
17. **P1. Horizontally clipped chip rows**: Today ("JUZ 30" cut at the edge, `06`), More prayer-day chips (`01-explore-more`), Dhikr presets ("ALLAHU A…", `07-more-dhikr`). The surah filter label "MEMORIZED" touches its borders.
18. **P2. Ayah 1 and Surah 1 headers.** The nav title switches between "SURAH 1" (eyebrow) and "Al-Faatiha" as you scroll. The big title block repeats the same information.

## D. Visual bugs
19. **P1. The prayer-times block on More is a blank ~120 pt gap** while loading or without location, then "Getting prayer times…" that never resolves without permission (`01-explore-more`, `01-more`).
20. **P1. Content ghosts through translucent headers** while scrolling (99 Names `12-…-scrolled`, More `14-…-scrolled`, Juz sheet `07-juz-scrolled`).
21. **P1. The Repeat sheet's material lets the reader's Arabic text show through** behind the rows (`16-loop-sheet`).
22. **P2. The Reading Type sheet re-wraps** "Immersive reading — hide controls" onto two lines after the face changes (`14-type-sheet-changed`).
23. **P2. The Memorization hub repeats "Nothing in review yet."** under two headings (`03-more-memorization`).
24. **P2. The last More rows (99 Names, Settings) sit under the tab bar.** The tour couldn't tap through to Islamic Calendar or Settings.

## E. Accessibility (from the UI-test failures)
25. **P1. Two buttons are labelled "More"** (the tab and the reader's `…`), which fails the UI test and is ambiguous for VoiceOver. The hidden tab bar stays in the accessibility tree inside the reader.
26. **P2. The tour couldn't find "Juz 30", "Play ayah", "Done" or the search field by label.** Several controls have labels that differ from their visible text.

## F. Code-level contributors (for the implementation plan)
Loop state duplicated (`SurahDetailViewModel.loopSettings` vs `AudioService.loopSettings`) · `PlayerScope` vs `LoopSettings.Mode` · three drill-button sets · `SurahDetailView.swift` at 1038 lines · no spacing tokens · ClipPlayer and GapClipPlayer duplicated.

## Not yet covered
Dark mode, the largest Dynamic Type sizes, landscape, offline or slow network, CarPlay, widgets, Settings and Calendar screens (the tour couldn't reach them), and onboarding (skipped by `-UITour`).
