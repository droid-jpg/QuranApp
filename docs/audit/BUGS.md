# Quran App: bug hunt (static reading only)

2026-11-09. Read-only pass over `Quran App/` and `QuranWidget/`. Nothing was built, run or tested, so every performance claim is a reading-based hypothesis and is labelled with a confidence level. Paths are relative to `Quran App/` (the inner folder) unless noted. Line numbers are from the working tree as it stood at the start of the pass.

## Summary

The per-tick playhead has already been split out of `AudioService` into `PlaybackClock` (`Services/AudioService.swift:12-16`), so the reader no longer re-renders ten times a second. The remaining lag has other causes: every discrete audio state change (ayah advance, play/pause, loop change) rebuilds every realised ayah row, which is expensive by construction; two perpetual animations run on a blurred material bar and a scrubber while audio plays; and opening the expanded player re-evaluates the whole 114-page pager inside a spring transaction. On correctness, the engine has several state-machine holes: the word loop overwrites `currentAyah` (so "Play from here" and the post-loop ayah tracking go wrong), a finished loop leaves a dead "loaded but empty" state (AUDIT #5), pausing during a Listen & Repeat gap does not cancel the scheduled resume, and the reader's stale loop copy overwrites the service's (AUDIT #8, confirmed). Prayer times are fetched only at launch and notifications are repeating fixed-clock triggers, so both go stale after the first day.

Count by severity (33 findings, no confirmed crash):

| Severity | Count |
|---|---|
| Crash | 0 |
| Wrong behaviour | 21 |
| Performance | 7 |
| Leak | 1 (Unverified) |
| Minor | 4 |

Confidence key: Confirmed = the failure follows from the code alone. Likely = follows from the code plus documented framework behaviour I could not execute. Unverified = plausible, needs a run or Instruments to settle.

---

## Performance while audio plays

**What changes while audio plays, and how often**

| Source | What publishes | Rate | Who observes it |
|---|---|---|---|
| `PlaybackClock.progress` (set in the periodic observer, `AudioService.swift:464-490`, interval 0.1 s) | `clock.objectWillChange` | ~10/s | Only `Scrubber` (`QuranPlayerView.swift:444`, inside the expanded player) and `LivePosition` (`HomeListeningCards.swift:115`, the Today resume card). Not the reader, not the ayah rows. |
| `PlaybackClock.duration` | same object | once per ayah | same two views |
| `AudioService` `@Published` (`isPlaying`, `currentAyah`, `currentSurah`, `currentSurahName`, `loopSettings`, `playbackRate`, `isWordLooping`) | `audioService.objectWillChange` | once per ayah advance, play/pause, loop edit (every few seconds to tens of seconds), coalesced per run loop | `SurahPageView`, every `SurahDetailView` (`@EnvironmentObject`, `SurahDetailView.swift:358`), `QuranPlayerBar`, `QuranExpandedPlayer`, `HomeView`, `ResumeListeningSection`, `HomeMiniPlayer`, `SurahListView` |
| `ListeningSessionStore.session` | on ayah change and on flush | once per ayah | `HomeView` |
| NowPlaying + session write | not published | 1/s (`AudioService.swift:482-487`), disk write every 5 s | nothing |
| Word loop observer (`AudioService.swift:496`) | nothing published | 20/s, trivial work | nothing |

So there is nothing left at 10 Hz in the reader except the two clock observers. The remaining frame drops come from the three causes below, ranked.

**Top three likely causes, ranked**

1. **Whole-reader rebuild on every audio state change, over rows that are expensive and never released (B1, B6, B7).** Each ayah row is a custom `FlowLayout` of one `ArabicWordChip` per word, with its own `@State`, `.sheet`, seven `@AppStorage`/`DynamicProperty` reads, and an O(words) lookup per word. `row(for:)` passes eleven closures, so SwiftUI cannot skip `AyahRowView.body`. `LazyVStack` keeps rows once realised, so after listening through a long surah hundreds of rows (thousands of chips) are re-evaluated on each ayah advance, at the same moment the 0.5 s animated `scrollTo` and the row highlight spring start. Cost grows the longer you listen or scroll. Likely.
2. **A perpetual animation inside a live blur, plus a scrubber that never stops animating (B2, B3).** While playing, `PlayingIndicatorView` runs five `repeatForever` height animations (layout-affecting, not transforms) inside a bar whose background is `.regularMaterial` over scrolling text (`QuranPlayerView.swift:128, 172`; same on Today, `HomeListeningCards.swift:259-267`). The scrubber and `ScrubLine` re-apply a `.linear` animation on every 0.1 s tick, so they are effectively always mid-animation. Together they keep the compositor re-blurring and the layout engine busy at display rate for the whole time audio plays, even when nothing else changes. Likely.
3. **Expanding the player re-evaluates the entire pager inside a spring (B4, B5).** `withAnimation(AppAnim.spring) { playerExpanded = true }` (`SurahDetailView.swift:116`) invalidates `SurahPageView.body`, which rebuilds a `TabView` with a `SurahDetailView` for all 114 surahs (`:95-106`) and creates their view models (`:99`), all under the animation transaction, while the overlay fades and slides in as one group-opacity layer (`QuranPlayerView.swift:226-229`) containing the live scrubber. Whether `TabView(.page)` realises all 114 pages is Unverified, but even without that, the body work and the group-opacity offscreen pass land in the same frames as the transition. Likely for the lag the user describes on expand.

To confirm without guessing: Instruments Animation Hitches and SwiftUI body counts; first experiment would be to remove `PlayingIndicatorView` and `.regularMaterial` from the bar and watch whether steady-state hitching stops (cause 2), then play through ayah 100 of Al-Baqarah and compare with ayah 5 (cause 1).

---

## Findings (most severe first)

### Wrong behaviour

**B1. [Performance] Every audio state change rebuilds all realised ayah rows**
- `Views/SurahDetailView.swift:358, 585-609, 675-679`; `Views/AyahRowView.swift:30-40, 259-267`
- Scenario: play Al-Baqarah from ayah 1 and keep listening or scrolling; each ayah advance, pause or loop change stutters, more so the further you have read.
- Cause: `SurahDetailView` observes `audioService`, and `row(for:)` builds `AyahRowView(... onBookmark: { }, onPlay: { }, ...)` with eleven fresh closures, so no row can be diffed away. Each row is a `FlowLayout` of per-word chips (`ForEach(Array(words.enumerated()) ...)`, `AyahRowView.swift:261`). `LazyVStack` does not unload realised rows.
- Fix: give rows only value inputs (`isPlaying`, flags) and an `Equatable` conformance with `.equatable()`, route actions through one environment object or an `id`-based callback, and render each ayah's Arabic as one text run (tappable words via attributed runs or a single hit-test) instead of a chip per word.
- Confidence: Likely (mechanism is certain; the frame cost needs Instruments).

**B2. [Performance] Perpetual `repeatForever` animation inside a live material bar**
- `Views/AnimationKit.swift:106-129`; `Views/QuranPlayerView.swift:127-129, 172`; `Views/HomeListeningCards.swift:259, 266-268`
- Scenario: audio playing, mini bar visible, user scrolls the reader; frames drop.
- Cause: `.frame(width: 2.5, height: animating ? heights[i] : 3)` animated forever (layout-affecting) on the material bar.
- Fix: draw the bars with `scaleEffect(y:)` or a `Canvas`/`TimelineView` limited to 15 fps, and give the bar an opaque `Color(.systemBackground)` fill instead of `.regularMaterial`.
- Confidence: Likely.

**B3. [Performance] Scrubber and ScrubLine are always mid-animation; drag seeks are unthrottled**
- `Views/QuranPlayerView.swift:464, 466-469`; `Views/HomeListeningCards.swift:159`; `Services/AudioService.swift:208-217`
- Scenario: expanded player open (or Today visible behind the reader); the playhead redraws continuously. Dragging the scrubber issues a zero-tolerance `seek` on every `onChanged` event on a streamed MP3.
- Cause: `.animation(.linear(duration: 0.12), value: frac)` re-triggered every 0.1 s; `player.seek(... toleranceBefore: .zero, toleranceAfter: .zero)` per drag event, plus `updateNowPlayingInfo()` each time.
- Fix: drop the implicit animation (the 0.1 s tick is already smooth), seek on drag end or coalesce while a seek is in flight, and use default tolerance during drag.
- Confidence: Likely. Also Unverified: `LivePosition` on Today stays alive under the pushed reader and keeps redrawing at 10 Hz while hidden.

**B4. [Performance] Expanding the player re-evaluates the whole pager inside a spring**
- `Views/SurahDetailView.swift:95-106, 116, 125-132`; `Views/QuranPlayerView.swift:226-229, 398, 606-610`
- Scenario: tap the mini bar; the expand animation hitches.
- Cause: `playerExpanded` lives in `SurahPageView`, whose body rebuilds 114 `SurahDetailView` values and calls `models.model(for:)` 114 times inside `withAnimation`; the overlay uses `.move.combined(with: .opacity)` on a large view (group opacity = offscreen pass); `keyWindowInsets()` walks `UIApplication.shared.connectedScenes` on every body evaluation of the expanded player.
- Fix: move `playerExpanded` and the overlay into a small child view so the pager does not invalidate; present the sheet with a plain `.move` transition or `.presentationDetents`; read the bottom inset once (GeometryReader or `safeAreaInset`).
- Confidence: Likely.

**B5. [Performance / Wrong behaviour] A `SurahDetailView` per surah, each with its own network `.task`**
- `Views/SurahDetailView.swift:95-106, 766-775`; `ViewModels/SurahDetailViewModel.swift` (one model per surah, held forever by `SurahModelStore`, `SurahDetailView.swift:21-31`)
- Scenario: open the reader. If `TabView(.page)` realises all pages, 114 pages each start `loadAyahs`, `loadWordTimings`, `loadWordDetails`, `loadTafsir` (up to ~450 requests) and every loaded surah's text, word details and tafsir stay in memory for the session. A translation change also fires `loadAyahs()` in every instantiated page (`:763-765`).
- Fix: window the pager to current ±1 (`ForEach(visibleIndices)`), and have `SurahModelStore` evict far models.
- Confidence: Unverified (depends on how `TabView(.page)` instantiates children on the target OS).

**B6. [Performance] FlowLayout measures every word twice per layout and has no cache; per-word O(n) lookup**
- `Views/FlowLayout.swift:14, 41`; `Views/AyahRowView.swift:255-257, 263`
- Scenario: any ayah layout pass re-measures all words twice; `detail(forDisplayIndex:)` does `wordDetails?.first { $0.position == i + 1 }` per chip, O(words²) per ayah per body.
- Fix: compute sizes once in a `Layout` cache; build a `[Int: WordDetail]` once per row.
- Confidence: Confirmed (code), cost Likely.

**B7. [Performance] Animated `scrollTo` on every ayah advance**
- `Views/SurahDetailView.swift:696-701`
- Scenario: auto-advance plays through ayahs; each change runs a 0.5 s animated scroll over a `LazyVStack` with unknown row heights, overlapping the B1 rebuild.
- Fix: scroll without animation when the target is more than a screen away, or only when the row is off-screen.
- Confidence: Likely.

**B8. [Wrong behaviour] Reader's stale loop copy overwrites the service's loop state (AUDIT #8)**
- `ViewModels/SurahDetailViewModel.swift:108-125`; `Views/SurahDetailView.swift:150-155`; `Services/AudioService.swift:152-157, 194-196`
- Scenario: start "Chain" from Today (or lock-screen repeat, CarPlay repeat, Siri), open the reader, tap "Play from here" on any ayah: the loop silently reverts to whatever the reader last applied (default Off). The Repeat sheet also opens from the stale copy. Each surah has its own model, so loops also do not follow you across a swipe.
```
audioService.play(surah: surah.number, startAyah: number,
                  loop: loopSettings, totalAyahs: surah.numberOfAyahs)
```
- Fix: make `AudioService.loopSettings` the only source; `playAyah` should pass `audioService.loopSettings` (or a `keepLoop` flag), and the sheet should read `audioService.loopSettings`. Delete `SurahDetailViewModel.loopSettings`.
- Confidence: Confirmed by reading. AUDIT #8.

**B9. [Wrong behaviour] Word loop overwrites `currentAyah`, so "Play from here" does nothing and later ayah tracking is wrong**
- `Services/AudioService.swift:229-233, 251-260, 369-387`; `Views/SurahDetailView.swift:503-506`; `ViewModels/SurahDetailViewModel.swift:113-124`
- Scenario A: listening at ayah 10, long-press ayah 3, Word by word, loop two words. Then tap "Play from here" on ayah 3: `stopWordLoop()` resumes the old ayah-10 item (`player.play()`, `isPlaying = true`), then `playAyah(3)` sees `currentAyah == 3` and calls `togglePlayPause()`, which pauses. Result: silence, ayah 3 never plays. Scenario B: word loop started from a cold player: `stopWordLoop()` sets `isPlaying = false`, `playAyah` toggles, the `player.currentItem != nil` guard returns, nothing happens. Scenario C: after stopping the loop, the old ayah-10 item finishes and `handleAyahEnd` computes the next ayah from `currentAyah == 3`, so the UI shows ayah 4 while ayah 11 plays.
```
currentSurah  = surah
currentAyah   = ayah      // line 231: ayah of the word loop, main item untouched
```
- Fix: keep a separate `wordLoopAyah` for the highlight and leave `currentAyah` pointing at the main queue item; make `stopWordLoop` restore the previous state rather than auto-resuming; give the UI an explicit "stop word loop".
- Confidence: Confirmed by reading. Related AUDIT #12.

**B10. [Wrong behaviour] A finished loop leaves a dead "loaded but empty" state (AUDIT #5)**
- `Services/AudioService.swift:405-408, 416-420, 431-435, 164`; `Views/HomeListeningCards.swift:21-25, 43-46`; `ViewModels/SurahDetailViewModel.swift:114-115`
- Scenario: play Verse of the Day (`repeatCount: 1`) or any counted loop to the end. The engine calls `player.removeAllItems(); isPlaying = false` but keeps `currentAyah` and `progress`. Today then shows "Paused" with a pause glyph and `0:03 / 0:03` (`isLive` is true because `currentAyah != nil`), and the play button calls `togglePlayPause()`, which returns at `guard player.currentItem != nil`. Same for the reader's row play and the mini bar: nothing happens. Same at the end of surah 114.
- Fix: on natural completion either call a `finish()` that sets `currentAyah = nil`/progress 0 (so UI returns to Resume), or keep the item and `seek(to: .zero)` so play restarts it. Make `togglePlayPause` reload `currentAyah` when the queue is empty.
- Confidence: Confirmed by reading. AUDIT #5 (the icon part is `HomeListeningCards.swift:45`, `pause.fill` used as a state glyph for "Paused").

**B11. [Wrong behaviour] Pause/play during a Listen & Repeat gap does not cancel the scheduled resume; stale tasks can double-load**
- `Services/AudioService.swift:159-168, 445-459`
- Scenario: Listen & Repeat gap running (`isPlaying == false`, `pausedForRepeat == true`). The button shows Play; tapping it sets `isPlaying = true` over silence (the item has ended), tapping again pauses, yet when the gap ends the pending task runs `work()` and playback restarts against the user's pause. The doc comment at `:84-85` says pause cancels it; `togglePlayPause` never clears `pausedForRepeat`. Separately, the `Task` is not stored or cancelled: if the user starts something new (`play()` clears the flag) and a new gap begins before the old sleep ends, the old task sees `pausedForRepeat == true` again and also fires, loading a stale ayah.
- Fix: store the task, cancel it in `togglePlayPause`/`play`/`stop`/`startWordLoop`, and make Play during a gap run `work()` immediately.
- Confidence: Confirmed by reading (first scenario); Likely (stale double-fire).

**B12. [Wrong behaviour] Starting a word loop during a repeat gap makes both players play**
- `Services/AudioService.swift:221-249, 453-458`
- Scenario: in a Listen & Repeat gap, open Word by word and start a loop. `startWordLoop` neither clears `pausedForRepeat` nor stops the gap task; when it fires, `loadItem` runs `player.play()` while `isWordLooping` is still true, so the chapter player and the ayah player play together.
- Fix: as B11, cancel the gap task in `startWordLoop`; guard `loadItem` against `isWordLooping`.
- Confidence: Likely.

**B13. [Wrong behaviour] Switching the loop to Off mid-play can desync queue and highlight**
- `Services/AudioService.swift:194-196, 267-290, 385-393`
- Scenario: loop mode is Single/Range (no follower is pre-queued, `:285`). User opens Repeat, picks Off, Apply. At the end of the current ayah `handleAyahEnd` takes the seamless branch: `currentAyah = nextAyah; playerItem = preloadedItem ?? player.currentItem`. Both are nil/empty, so no end observer is installed, and `nextNext` (ayah+2) is inserted into the empty queue. The UI highlights ayah+1 while ayah+2 plays, and playback then stops after that item because nothing observes its end.
- Fix: in `updateLoop`, rebuild the queue (`loadItem(ayah: currentAyah)` at the current position or re-seed the preloaded item) when the mode changes; in the seamless branch, fall back to `loadItem(ayah: nextAyah)` if `preloadedItem` is nil.
- Confidence: Likely (depends on when AVQueuePlayer drops the finished item relative to the notification).

**B14. [Wrong behaviour] Playback speed resets to 1x on resume**
- `Services/AudioService.swift:166, 258, 550, 198-203`
- Scenario: set 1.5x, pause, resume (or return from a phone call, or stop a word loop): `player.play()` starts at the default rate; the pill still says 1.5x. `loadItem` re-applies the rate (`:296`), the resume paths do not. Setting speed while paused is stored but not applied either.
- Fix: set `player.defaultRate = playbackRate` in `setPlaybackRate`, or set `player.rate = playbackRate` after every `play()`.
- Confidence: Likely.

**B15. [Wrong behaviour] No handling of item load failures or stalls**
- `Services/AudioService.swift:267-307` (no status or `AVPlayerItemFailedToPlayToEndTime` observer anywhere)
- Scenario: network drops mid-surah, or everyayah.com returns an error for the next ayah. `isPlaying` stays true, the highlight and bar show playing, nothing advances, no message.
- Fix: observe `item.status` / `.AVPlayerItemFailedToPlayToEndTime`, set `isPlaying = false`, and either skip to the next ayah or surface an error.
- Confidence: Confirmed that the handling is absent; effect Likely.

**B16. [Wrong behaviour] Prefetch cache and downloads store HTTP error bodies as audio; failed downloads count as complete**
- `Services/AudioPrefetchCache.swift:28-34`; `Services/DownloadManager.swift:61-72, 86-97, 143-147`; `Services/AudioService.swift:318-321, 312`
- Scenario: a 404/5xx or captive-portal HTML comes back, `URLSession.downloadTask` reports no error, and the file is moved into `quran_prefetch` (or, for downloads, `quran_audio/...`) with an `.mp3` name. `audioURL` prefers local files, so that ayah fails to play until the temp folder is purged (downloads: never). In `downloadSurah` an error is swallowed with "still count toward progress", so a surah with failed ayahs reaches 1.0, is recorded in `downloaded_surahs_v1`, and `surahHasFiles` only checks that the folder is non-empty.
- Fix: check `(response as? HTTPURLResponse)?.statusCode == 200` and a minimum size before moving; count only successes toward completion and keep failures retryable.
- Confidence: Confirmed by reading.

**B17. [Wrong behaviour] "This ayah" loop ignores the ayah chosen in the sheet**
- `Services/AudioService.swift:410-416`; `Views/LoopSettingsSheet.swift:103-113`
- Scenario: Repeat sheet, mode This ayah, Stepper to ayah 12, Apply, while ayah 3 plays (or "Play from here" on ayah 7): the engine loops `currentAyah`, not `loopSettings.startAyah`. The stepper only matters when started through `playLoop`.
- Fix: either drop the stepper in single mode or have `.single` end-handling jump to `loopSettings.startAyah`.
- Confidence: Likely.

**B18. [Wrong behaviour] Prayer times and notifications go stale after the first day**
- `Services/PrayerTimesService.swift:122, 54-57, 88-107`; `Services/NotificationService.swift:46-49, 129-133`; `Quran_AppApp.swift:158-162`; `Views/HomeView.swift:456-465`
- Scenario: times are fetched once per launch for "today" (`bySettingHour ... of: Date()`). Notifications are scheduled as `UNCalendarNotificationTrigger(repeats: true)` at that day's hour:minute, so every later day fires at the first day's clock time even though prayer times shift daily, until the app is launched again. `requestAndFetch()` is not called on foreground, so a suspended app kept overnight shows yesterday's times; `NextPrayerSection` falls to `fajr + 86400`, which is already past (countdown "in 0s"). The widget's `prayerTimesDict` has the same staleness.
- Fix: refetch on `scenePhase == .active` when the day changed; schedule per-day non-repeating requests for the next ~7 days (the API can return a month) instead of repeating triggers.
- Confidence: Confirmed by reading.

**B19. [Wrong behaviour] Prayer card gets stuck on "Getting prayer times…" or shows a blank gap (AUDIT #19)**
- `Services/PrayerTimesService.swift:68-72, 105-108, 168-172`; `Views/PrayerTimesCardView.swift:31-40, 233-258`
- Scenario: (a) the server returns JSON without `data.timings`: `fetchTimes` sets `locationError` and returns without changing `fetchStatus`, which stays `.fetching` forever. (b) A network error or `didFailWithError` (e.g. simulator with no location, location unavailable) sets `.ready` with `prayerTimes == nil`; `PrayerTimesForDayView` then renders `Color.clear.frame(height: 70)`, the blank gap, with no message and no retry (`locationError` is never displayed). The `.denied` path itself is handled correctly (`:98-99`, `:136-138`), so the reported "never resolves without permission" is not reproduced from the code for a real denial; the stuck states are the two above.
- Fix: add `.failed(String)` status, set it on every early return and error, show message plus Retry.
- Confidence: Confirmed by reading (code paths); AUDIT #19 partly matched.

**B20. [Wrong behaviour] Day view copies times once; offset cache never invalidates**
- `Views/PrayerTimesCardView.swift:236-248`; `Services/PrayerTimesService.swift:21, 155-160`
- Scenario: change calculation method or Asr school while More is showing today: `refetchForSettingsChange()` updates `prayerTimes`, but `PrayerTimesForDayView` copied `service.prayerTimes` in `.task(id: dayOffset)` and only re-runs when the offset changes, so the list shows old times. `dailyTimings` is keyed by offset from today and never cleared across midnight, so "Tomorrow" (offset 1) shows yesterday's cached tomorrow.
- Fix: key the cache by date string; read `service.prayerTimes` directly for offset 0.
- Confidence: Confirmed by reading.

**B21. [Wrong behaviour] Notification permission prompt at launch (AUDIT #4)**
- `Quran_AppApp.swift:157-160`; `Views/OnboardingView.swift:142-159`
- Scenario: a user who finishes onboarding without tapping "Enable Reminders" gets the system notification prompt on the next cold launch, over Today, with no context. It also blocks `performPendingHifzAction()` (`:166`) behind the prompt, delaying a Siri "Continue Memorizing". The `-UITour 1` launch argument used by the tour is not read anywhere in the app (grep), so the prompt in the tour screenshots comes from this path.
- Fix: never call `requestPermission()` at launch; request only from the Settings toggles and onboarding.
- Confidence: Confirmed by reading.

**B22. [Wrong behaviour] Auto-continue to the next surah loses the name and orphans the reader's player**
- `Services/AudioService.swift:396-403`; `Views/SurahDetailView.swift:79-81, 137-139`
- Scenario: reader on Al-Fatiha with sequential playback; at ayah 7 the service switches to surah 2 with `currentSurahName = "Surah 2"` (English name lost in Now Playing and the Today bar). Because `playerActive` requires `currentSurah == surah.number`, the reader's mini bar disappears and the expanded player closes while audio keeps going, with no on-screen control. The new surah's `recordPlay` is not called, so resume bars are stale.
- Fix: look up the name from the surah list; let the reader follow `currentSurah` (move the pager) or keep the bar visible for any playing surah.
- Confidence: Confirmed by reading.

**B23. [Wrong behaviour] Streak count never decays**
- `Services/StreakService.swift:10-12, 15-37`
- Scenario: read for 5 days, skip 3: the Today masthead still says "5 DAYS" until the next read (the reset only happens in `recordRead`). `Masthead(streak:)` is also not reactive, so it updates only when Home re-evaluates.
- Fix: compute the displayed streak from `lastReadDate` (zero if older than yesterday).
- Confidence: Confirmed by reading.

**B24. [Wrong behaviour / Performance] Reader waits for the network before using its on-disk cache**
- `Services/QuranAPIService.swift:31-48`
- Scenario: open a previously read surah on a weak connection: "Loading ayahs…" for up to the URLSession timeout (60 s) although the surah is cached in `quran_text`. The cache and bundled text are consulted only after the request throws.
- Fix: show cached or bundled text immediately and refresh in the background.
- Confidence: Likely.

**B25. [Wrong behaviour] CarPlay launched without the phone UI has no audio service**
- `Quran_AppApp.swift:150-153`; `Services/CarPlayTemplateManager.swift:9-10, 169-171`
- Scenario: the bridge is populated in the WindowGroup `.task`. If CarPlay connects before the phone scene runs (cold start in the car), `audio` and `memory` are nil: Memorized lists are empty, taps call `audio?.play` as no-ops, and `observeAudio()` returns at `guard let audio` and never subscribes. Also `fetchSurahList` failure leaves the Browse tab empty with no retry.
- Fix: create `AudioService`/stores in a shared singleton, not in a View-owned `@StateObject`; retry in `connect`.
- Confidence: Unverified (needs a CarPlay cold start).

**B26. [Wrong behaviour] Progress and Now Playing freeze during a word loop**
- `Services/AudioService.swift:466, 482-487`
- Scenario: word loop running: the observer returns at `guard ... !self.isWordLooping`, so `progress` stays at the old ayah's value and Now Playing is not refreshed; lock screen and Today show a stale position. (AUDIT #12 covers the loop being a separate system.)
- Fix: drive progress from the chapter player in a word loop, or hide the scrubber.
- Confidence: Confirmed by reading.

**B27. [Wrong behaviour] Reps shown with scope Off, summary text wrong (AUDIT #9, #11)**
- `Views/QuranPlayerView.swift:80-93, 281-284`; `Services/AudioService.swift:373-409`; `Views/HomeListeningCards.swift:207-214`
- Scenario: scope Off still shows the Reps control; `.off` mode ignores `repeatCount`. `summary` appends `×reps` whenever `reps > 0`, so the one-shot Verse of the Day (`repeatCount: 1`) reads "looping ×1"; Range reads "chaining 3–4" regardless of count. Three separate copies of the text exist.
- Fix: hide Reps when Off; one shared `LoopSettings.summary`.
- Confidence: Confirmed by reading. AUDIT #9, #11.

**B28. [Wrong behaviour] AUDIT #6 (pause icon after Stop) not reproduced from code**
- `Services/AudioService.swift:170-181`; `Views/QuranPlayerView.swift:308-311`; `Views/SurahDetailView.swift:79-81, 112-121`
- `stop()` sets `currentAyah = nil` synchronously, which removes both the reader bar (`playerActive`) and Today's `HomeMiniPlayer` (`isPlayerActive`). The screenshot is probably the bar during its 0.4 s removal transition or the B10 state. Marking Unverified; verify by running Stop from the expanded player.
- Confidence: Unverified.

### Persistence and data

**B29. [Minor] Decode failure silently empties a store, and the next save overwrites the data**
- `Services/BookmarkStore.swift:61-67`; `Services/MemorizationSRStore.swift:236-242`; `Services/MemorizationTargetStore.swift:111-117`; `Services/MemorizationStore.swift:95-104`
- Scenario: a future model change makes `JSONDecoder` throw; `load()` returns early, the in-memory store is empty, the next bookmark/review/enrol writes the empty-plus-one state over the old blob. `AyahReview` already has a tolerant `init(from:)`, the others do not.
- Fix: keep the raw blob (copy to a `.bak` key) when decoding fails and do not save until the user changes something after a successful load.
- Confidence: Likely (data loss only after a schema change).

**B30. [Minor] Memorization reminder text goes stale**
- `Services/NotificationService.swift:104-129`
- The body ("Continue Al-Mulk, ayah 12") is baked into a repeating trigger at scheduling time and refreshed only at launch, so it names an old ayah after progress without a relaunch.
- Confidence: Confirmed by reading.

**B31. [Minor] Short-clip players have no failure path and play over the main audio**
- `Services/ClipPlayer.swift:19-33, 79-100`
- A word clip that fails to load never reaches `finish()`, so `playingURL` stays set and the sheet shows STOP forever; `GapClipPlayer` never stops if `toMs` is past the file end. Neither pauses or ducks the main `AudioService` playback, so a tapped word plays on top of a running recitation.
- Confidence: Likely.

### Layout

**B32. [Minor] Translucent chrome and sheet backgrounds (AUDIT #20, #21); #24 and #17 not confirmed**
- `Quran_AppApp.swift:71-78` (all three nav-bar appearances, including `scrollEdgeAppearance`, use `configureWithDefaultBackground()`, i.e. a translucent blur, so scrolling content shows through the title bars in More/99 Names/Juz sheet: AUDIT #20); `Views/LoopSettingsSheet.swift:173-174` (`.presentationDetents([.medium, .large])` with a plain `Form` and no `.presentationBackground`, so the reader's Arabic shows through the sheet material: AUDIT #21).
- Fix: `appearance.configureWithOpaqueBackground()` plus `.presentationBackground(Color(.systemBackground))`.
- Confidence: Likely.
- AUDIT #24 (last More rows under the tab bar): the bar is a `safeAreaInset` on the `TabView` (`Quran_AppApp.swift:117-122`) and `MoreView` has `.padding(.bottom, 40)` (`Views/MoreView.swift:77`); I could not tell whether the inset reaches each tab's `ScrollView` with the system tab bar hidden. Unverified.
- AUDIT #17 (clipped chips): the rows are horizontal `ScrollView`s (`HomeListeningCards.swift:182`, `PrayerTimesCardView.swift:201-224`) so a chip cut at the edge is ordinary overflow with no peek or fade cue; not a code defect as such. Unverified.

### Leak

**L1. [Leak] Long-lived observers and models never released (Unverified, low impact)**
- `Services/AudioService.swift:353, 532, 556, 574-606` (observer tokens and remote-command targets are never removed; there is no `deinit`); `Views/SurahDetailView.swift:21-31` (`SurahModelStore` holds up to 114 models with ayahs, word details and tafsir for the life of the reader).
- `AudioService` is created once as an App `@StateObject`, so observers are registered exactly once and leak only if that ever changes. The model growth is the real cost and ties to B5.
- Confidence: Unverified.

---

## Looked at, found nothing

- **Per-tick publishing from `AudioService`**: only `clock` ticks; nothing else at tick rate (`AudioService.swift:461-490`). NowPlaying is throttled to 1 Hz; session record to 5 s writes.
- **Time observer lifecycle**: one main observer, installed once; chapter observer removed in `teardownChapterPlayer` (`:629-638`); `GapClipPlayer` removes its observer in `stop()`.
- **End-of-item observer**: one at a time, removed before re-adding (`:362-367`, `:268`); handler is `[weak self]` and runs via `MainActor.assumeIsolated` on `.main`.
- **Remote commands** are registered once in `init` (`:98-99`), `[weak self]` closures, no duplicates. Interruption and route-change handlers exist and resume only on `.shouldResume`.
- **Off-by-one at the surah ends in sequential mode**: `ayah < totalAyahs` guards, `nextAyah < totalAyahs` guard on the follower, `ayah > 1` in `skipToPrevious`, and surah 114 end handled (aside from B10).
- **Repeat-count arithmetic**: `repeatCount` N plays N times in single and segment (`:413, :427`); `0` is infinite.
- **Forced unwraps / indexing**: the hard-coded URL literals and `all[0]` fallbacks are safe; `surahs[idx]` in `SurahPageView` is clamped (`:71, :74`); `ReviewSessionView` guards `removeFirst`; `DownloadManager`'s `1...ayahCount` is only unsafe for `ayahCount == 0`, which never occurs.
- **`MainActor` isolation**: `AudioService`, stores and `DownloadManager` are `@MainActor`; CLLocationManager delegate methods hop with `Task { @MainActor [weak self] in }`. `BookmarkStore` and `MemorizationStore` are not annotated but are only touched from views.
- **Siri hand-off** (`HifzIntentAction.take()` is one-shot, so the double call at `.task` and `.active` cannot double-play).
- **Widget**: reads shared-group keys loosely (`QuranWidget.swift:103-130`); a new field in the app's models cannot blank it. App-group suite name is the same literal in `SurahDetailView.swift:782` and `sharedAppGroup`.
- **Qibla**: updates started on appear and stopped on disappear (`QiblaView.swift:32-33`).
- **Denied/restricted location**: handled in `requestAndFetch` and `locationManagerDidChangeAuthorization`.
- **CloudSync**: dormant by design, not assessed.

## Not examined

- `Views/SurahListView.swift` list/search body cost, `SurahListViewModel`, `JuzBrowserView`, `MushafView`, `NamesOfAllahView`/`NamesFlashcardView`, `NamesStore`, `DhikrView`/`DhikrStore`, `IslamicCalendarView`, `SettingsView` write paths.
- `WordTimingService`, `WordDetailService`, `TafsirService`, `QuranOfflineStore` parsing (only `QuranAPIService` and the callers' use of them were read).
- `PrayerLiveActivityService` and the Live Activity widget; `QuranWidgetLiveActivity.swift`.
- `ReviewSessionView` drill logic beyond the queue handling; SM-2 maths in `AyahReview`.
- Background-audio entitlements and Info.plist (`UIBackgroundModes`), CarPlay scene configuration, and Dynamic Type layouts.
- Anything that needs a running app: actual frame cost, AVQueuePlayer end-of-queue timing (B13, B14 depend on it), whether `TabView(.page)` is eager (B5).
