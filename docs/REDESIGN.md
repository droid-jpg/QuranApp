# Quran App: UX redesign

2026-11-09 · Design only. Inputs: `docs/audit/AUDIT.md`, `docs/audit/ARCHITECTURE.md`, `docs/audit/key-screens-01.jpg`. Nothing here was checked against the Swift source; file names in the plan come from ARCHITECTURE.md.

## 0. The decisions in one page

1. **Every surah row has a play button**, on every screen that lists surahs. Launch → Quran tab → play = 2 taps.
2. **One mini player, app-wide, restored paused on launch.** Its play button is the 1-tap resume from any tab. Today no longer has its own playback card, quick-start rail or mini player.
3. **One repeat model: "Repeat ayahs A–B, N times, with an optional pause."** A single ayah is just A = B, so "This ayah" vs "Range" stops being a mode. One sheet edits it, one function describes it, `AudioService` is the only owner.
4. **Listen / Repeat / Chain leave the listener's UI.** They become three presets inside Memorization that write the same repeat state. Pause-to-repeat becomes one row in the Repeat sheet. Word loop becomes a toggle inside Word by word.
5. **The word is "Repeat".** "Loop", "Reps", "drill" and "chain" do not appear outside Memorization. The book is spelled **Quran** everywhere.
6. **Ayah actions drop from 9 to 4 buttons plus 3 rows**, opened from a visible button on each ayah, not only long-press.
7. **No tiny caps.** Nothing a user must read is under 13 pt or letter-spaced. Bars and sheets are opaque.
8. **Connected surfaces.** Prayer card → Prayer Times. Date → Islamic Calendar. Verse of the day → the reader at that ayah. Mini player → Now Playing.

**Cut or demoted** (to reduce bloat): Today quick-start rail, Today resume card, `HomeMiniPlayer`, Today memorization block on a fresh install, the expanded player's drill row / scope segment / reps / range card, the mini-bar repeat cycle button, the Stop button, the surah-list filter segment (becomes a menu), the reader's top-bar Repeat button, `WordLoopPicker` as a separate sheet, the inline prayer block on More, the reader's large header play circle and the duplicate "SURAH 1" eyebrow.

## 1. Information architecture

Three tabs with icon + label: **Today**, **Quran**, **More**. The mini player sits above the tab bar on all three and at the bottom of the reader. Now Playing and Repeat are sheets available from anywhere the mini player is.

```
Today ─┬─ Search field ──────────► Quran tab, search focused
       ├─ Recent surah rows ─────► play in place / open Reader
       ├─ Next prayer card ──────► Prayer Times
       ├─ Date line ─────────────► Islamic Calendar
       └─ Verse of the day ──────► Reader at that ayah
Quran ─┬─ Surah rows ────────────► play in place / open Reader
       └─ Juz (toolbar) ─────────► Juz list, rows also play
More ──── Prayer Times · Qibla · Dhikr · Bookmarks · Memorization · 99 Names · Islamic Calendar · Settings
Reader ── Ayah actions sheet · Reading type · Tafsir · Word by word · Mushaf
Mini player (everywhere) ─► Now Playing ─► Repeat sheet
```

| Current feature | New location |
|---|---|
| Play a surah | Play button on every surah row (Today Recent, Quran list, search results, Juz list); "Play" in the reader's title block |
| Resume last playback | Mini player, restored paused at launch |
| Last loop (Today rail) | Today → Recent: the row remembers its repeat range and resumes it |
| Juz 30 shortcut | Quran → Juz → row 30 play button |
| Verse of the day | Today, one card; tap opens the reader at the ayah |
| Today resume card, `HomeMiniPlayer` | Removed; replaced by the app-wide mini player |
| Prayer card on Today | Today, tappable → Prayer Times |
| Prayer block on More | Row "Prayer Times" with the next prayer as its trailing value |
| Islamic calendar link | Today date line; More → Islamic Calendar |
| Memorization summary on Today | Today only when at least one surah is in progress; otherwise More → Memorization |
| Listen / Repeat / Chain | More → Memorization only, as presets (§4.4). Siri "Continue Memorizing" uses the same presets |
| Reader "Repeat" sheet, expanded-player loop controls, mini-bar cycle | One Repeat sheet (§3.6) |
| Row "Repeat this ayah" | Ayah actions → **Repeat** |
| Pause to repeat + gap | Repeat sheet → "Pause after each ayah" |
| Word-by-word loop, `WordLoopPicker` | Ayah actions → Word by word → "Repeat selected words" |
| Tafsir, Bookmark, Share ×2, Add to review, Memorize from here | Ayah actions (§3.7) |
| Bookmarks list | More → Bookmarks (unchanged); bookmarking is now a visible button |
| Surah filters All / Offline / Memorized / Learning | Quran → Filter menu: All, Downloaded, Memorized, Learning |
| Juz browser | Quran toolbar button "Juz" (unchanged sheet, plus play buttons) |
| Speed | Now Playing → Speed |
| Reciter | Settings; also Now Playing → `…` → Reciter |
| Stop | Removed. Pause is the only stop; Now Playing → `…` → "Close player" clears the session |
| Reading type, Mushaf, download, immersive reading | Reader `Aa` and reader options menu (unchanged) |
| Qibla, Dhikr, 99 Names, Settings, widgets, CarPlay, Live Activity, iCloud, onboarding | Unchanged location |
| Notification permission | Asked only when the user turns on prayer notifications or the daily reminder, never at launch |

## 2. Vocabulary (one spelling, one meaning)

| Use | Never |
|---|---|
| Quran | Qur'an, Holy Quran (as a screen title) |
| Surah, Ayah / Ayahs | Verse (except the fixed name "Verse of the day"), Aya |
| Repeat (the one feature) | Loop, Reps, Chain, Drill, Segment |
| Times | Reps, ×1 |
| Downloaded | Offline |
| Memorization, Learning, Memorized | Memorize hub, In progress |
| Now Playing | Expanded player |
| Reader options (accessibility label of the reader `…`) | More |

Rule: no caption that explains a control. If a label needs a sentence under it, rename the control. Every accessibility label equals the visible text (AUDIT #26).

## 3. Screen specs

Shared rules: screen margin 20 pt; scroll content always gets a bottom inset equal to tab bar + mini player, so nothing sits under a bar (AUDIT #24). Navigation and tab bars are opaque `surface` with a hairline (AUDIT #20).

### 3.0 Swipe navigation

One rule for every horizontal swipe: it only starts after 12 pt of travel that is at least twice as horizontal as vertical, it follows the finger, and it commits past 40% of the screen width or on a flick; otherwise it springs back. Vertical scrolling therefore never triggers it.

| Where | Swipe | Result |
|---|---|---|
| Root of Today, Quran, More | left / right anywhere | Adjacent tab (Today ↔ Quran ↔ More). Off while the keyboard is up |
| Any pushed screen (incl. reader) | right, starting in the **left 32 pt** | Back, interactive |
| Reader | left / right starting **outside** the left 32 pt | Previous / next surah |
| Mini player | up | Now Playing |
| Now Playing, sheets | down | Dismiss |

The 32 pt zone is the boundary between "leave the surah" and "change surah"; it coincides with the ayah-number gutter, so it never starts on Arabic text. Tab swiping is off on pushed screens, so it cannot fight back or surah paging. No list has row swipe actions, and no horizontal chip rows remain, so nothing else competes for the gesture.

### 3.1 Today

**Purpose:** start listening in one tap, see the next prayer, read one verse.

Top to bottom:
1. **Header.** Greeting as the title ("Good evening", Display). Below it the date line "Mon 9 Nov · 29 Jumada I" (Secondary, sentence case), a button → Islamic Calendar.
2. **Search field.** Placeholder "Search surahs". Tapping it switches to the Quran tab with search focused.
3. **Recent.** Section heading "Recent". Up to 3 surah rows (the §3.2 row). Subtitle shows where you were: "Ayah 142" or "Ayahs 255–257, repeating". Play resumes that position and that repeat range.
4. **Next prayer card.** "Maghrib" (Heading) · "5:02 PM" (Heading, trailing) · "in 1 h 12 min" (Secondary). Whole card is a button → Prayer Times, with a chevron.
5. **Verse of the day.** Heading "Verse of the day" with "Taa-Haa 25" trailing; Arabic; translation in Body, full contrast; a 44 pt play button. Tapping the text opens the reader at that ayah.
6. **Memorization row** (only if a surah is Learning): "Memorization · 2 learning, 5 memorized" → Memorization.

States:
- **Fresh install:** section 3 is headed "Start listening" and lists Al-Faatiha, Yaseen, Al-Kahf, Al-Mulk (app's existing transliterations) with play buttons. No blank lower half (AUDIT #1).
- **Playing:** the playing surah's row, if visible, shows a pause icon and accent title. Nothing else on Today changes; state lives in the mini player (AUDIT #5).
- **Prayer loading:** card keeps its height, shows "Getting prayer times…". **No location:** "Prayer times need your location" + button "Allow location". **Error:** "Couldn't load prayer times" + "Try again".
- **VOTD audio error:** inline "Couldn't play. Try again" replacing the play button's label for that card.

### 3.2 Surah list (Quran tab)

**Purpose:** find a surah; play it or open it.

1. **Title** "Quran" (Display). Trailing toolbar: **Juz** button, **Filter** menu (All, Downloaded, Memorized, Learning; a dot marks an active filter). No "114 surahs" counter.
2. **Search field** "Search surahs" (name, meaning or number).
3. **Rows**, min height 64 pt:
   - leading: number (Secondary, 28 pt column)
   - title: "Al-Baqara" (Row title, serif); subtitle "The Cow · 286 ayahs" (Secondary, not italic, not caps)
   - trailing: Arabic name (Arabic 20), then a **44 pt play button**. No chevron.
   - Tap row → reader. Tap play → starts from ayah 1 (or the saved position if this surah is the current session) without leaving the list. Tap again → pause.
   - Small "downloaded" glyph after the subtitle when available offline.
   - Context menu: Play, Download / Remove download, Mark as memorized.

States: **playing** row has pause icon + accent title; **loading audio** shows a spinner in the play button; **audio error** shows a banner above the mini player "Couldn't play Al-Baqara. Try again" and the button returns to play; **no search results** "No surahs match 'xyz'"; **empty filter** "No downloaded surahs yet".

Juz sheet: same row shape ("Juz 30 · An-Naba to An-Nas"), same play button.

### 3.3 Reader

**Purpose:** read; start audio or a repeat from any ayah.

1. **Top bar** (opaque): back · title "Al-Faatiha" always (no switching eyebrow, AUDIT #18) · `Aa` (label "Reading type") · `…` (label "Reader options": Mushaf view, Download, Hide controls while reading, Share surah).
2. **Title block**, compact: "Al-Faatiha" (Title), "The Opening · Meccan · 7 ayahs" (Secondary), then one filled button **Play** (becomes **Pause** when this surah is playing). "Surah 1" is not repeated.
3. **Ayahs.** Each: Arabic (reader type settings), transliteration (Secondary italic, `textSecondary`), translation (Body, `textPrimary`). The leading ayah number is a 44 pt button, accessibility label "Ayah 4 actions", which opens Ayah actions. Long-press on the ayah does the same. A tap on a word keeps its current meaning: it plays that word.
4. **Mini player** at the bottom safe area (the tab bar is hidden and removed from the accessibility tree, AUDIT #25).

States:
- **Playing:** the current ayah has a `highlight` background and a 3 pt accent bar; the reader auto-scrolls to keep it visible unless the user scrolled in the last 5 s.
- **Repeat on:** ayahs in the range get a thin accent rule in the leading gutter, so the range is visible in the text.
- **Loading text:** title block plus 3 skeleton ayahs. **Text error:** "Couldn't load this surah" + "Try again". **Audio error:** banner above the mini player.
- **Hide controls while reading:** top bar and mini player hide; tap anywhere restores them.

Swiping: left-edge swipe goes back, a swipe anywhere else changes surah (§3.0).

### 3.4 Mini player (app-wide)

**Purpose:** always-visible state and play/pause; door to Now Playing and Repeat.

Mounted once at the root, above the tab bar, 56 pt tall, opaque `surfaceRaised`, with a 2 pt progress line along its top edge.

- Left (tap → Now Playing; swipe up does the same): title "Al-Baqara" (Row title, 17), subtitle from the single status function (§4.3): "Ayah 255 · Mishary Al-Afasy" or "Repeating ayahs 255–257 · 2 of 5".
- Right: **Repeat** button (44 pt; outlined when off, filled accent when on; opens the Repeat sheet) and **Play/Pause** (44 pt).

States: **hidden** when there has never been a session; **restored** paused at launch with the last session; **playing**; **paused** (play icon, never a pause icon while paused, AUDIT #5/#6); **loading** (spinner in the play button); **error** (subtitle "Couldn't play. Tap to retry" in `danger`). Hidden in the reader only while controls are hidden.

### 3.5 Now Playing

**Purpose:** see and control what is playing. Three control rows, not six (AUDIT #14).

Full-height opaque sheet (not an overlay on a dimmed reader, and no blur or material: the current overlay is where you see the worst lag). Top to bottom:
1. Grabber; `…` trailing (Go to ayah in reader, Reciter, Close player).
2. "Al-Faatiha" (Title); "Ayah 4 of 7 · Mishary Al-Afasy" (Secondary).
3. The current ayah: Arabic, then translation (Body). This fills the free space and scrolls if long.
4. **Ayah bar:** one track for the whole surah, thumb at the current ayah, labels "1" and "7". Drag to jump to an ayah. When Repeat is on, the range is drawn as an accent span on the track. This replaces the 4-second time scrubber.
5. **Transport:** Previous ayah · Play/Pause (64 pt) · Next ayah.
6. **Options row**, two labelled buttons: **Repeat** (value under it: "Off" or "Ayahs 3–4 · 5 times") opens the Repeat sheet; **Speed** (value "1×") opens a menu of the existing rates.

States: paused; playing; loading (spinner in play); error ("Couldn't play ayah 4" + "Try again" in place of the ayah text); word repeat active (line 2 reads "Repeating words 2–4 of ayah 5", ayah bar disabled).

### 3.6 Repeat control (the only one)

**Purpose:** choose which ayahs repeat and how many times.

One sheet, medium detent, opaque `surfaceRaised` (AUDIT #21). Opened from the mini player, Now Playing, and Ayah actions → "More repeat options". There is no Cancel/Apply: changes apply as they are made; the only button in the bar is **Done**.

1. Title "Repeat" with the surah name under it. Trailing **switch** (label "Repeat").
2. Disabled and dimmed while the switch is off (AUDIT #9):
   - **From** — "Ayah 3" with −/+ steppers; tap the value for a wheel picker. First words of the ayah in Arabic as a trailing preview.
   - **To** — same. To can never be less than From; moving one past the other drags the other with it.
   - Shortcuts, two text buttons: **This ayah only** · **Whole surah**.
   - **Times** — segmented: `2` `3` `5` `10` `∞` (default ∞).
   - **Pause after each ayah** — segmented: `None` `Ayah length` `5 s` `10 s` (default None).
3. Summary line (the §4.3 string), e.g. "Ayahs 3–4, 5 times, pausing after each".
4. When nothing is playing: primary button **Play ayahs 3–4** (or **Play ayah 3**). When audio is already playing the button is absent, because the change is already live.

States: off (rows dimmed); on; From = To (labels read "Ayah 3", shortcut "This ayah only" shown as selected).

### 3.7 Ayah actions

**Purpose:** everything you can do with one ayah, without a 9-row menu (AUDIT #15).

Sheet, medium detent, opaque. Opened by the ayah-number button or long-press.

1. Header: "Al-Faatiha · Ayah 4", one line of Arabic, one line of translation.
2. **Four buttons** in a row, icon above label, each at least 64 × 64 pt:
   - **Play** — plays from this ayah, closes the sheet.
   - **Repeat** — sets From = To = this ayah, ∞, starts playing, closes. If Repeat is already on in this surah and this is a different ayah, the label is **Repeat to here** (ayah after From) or **Repeat from here** (ayah before From), and it extends the range. If this ayah is the whole range, the label is **Stop repeating**.
   - **Bookmark** / **Bookmarked**.
   - **Share** — opens a small menu: "Arabic only", "With translation".
3. **Three rows:** Tafsir · Word by word · Add to memorization (replaces both "Memorize from here" and "Add to review"; Memorization decides which applies).
4. Text button: **More repeat options** → Repeat sheet, prefilled with this ayah.

Looping two ayahs is therefore: ayah 3 number → Repeat → ayah 4 number → Repeat to here.

**Word by word** sheet: the ayah's words as tappable chips (tap = hear the word). Toggle **Repeat selected words**: when on, tap the first and last word; the selection repeats until the toggle is turned off or the sheet closes. Main playback pauses while it runs and the mini player says so (AUDIT #12).

### 3.8 More

**Purpose:** everything that is not reading or listening.

Title "More" (Display). A plain list, one row per item, icon + title (Row title) + optional trailing value, min height 56 pt:

Prayer Times (value "Maghrib 5:02 PM") · Qibla · Dhikr · Bookmarks (count) · Memorization · 99 Names · Islamic Calendar (Hijri date) · Settings

No inline prayer block, no day chips (AUDIT #17, #19). The list scrolls clear of the tab bar and mini player (AUDIT #24).

States: prayer value shows "Location needed" or "—" while loading; never a blank gap.

**Prayer Times** (pushed from More or Today): today's five prayers plus sunrise as rows, next prayer highlighted; day switcher as previous/next arrows around the date (not a clipped chip row); "Notifications" row → the existing per-prayer toggles. The permission prompt is triggered here.

### 3.9 Memorization (brief, since it is rarely used but kept)

- Hub: one "Review" section with one empty state "Nothing to review yet" (AUDIT #23).
- The surah grid becomes a **list grouped by status** (Learning, Memorized, Not started collapsed by default), using the standard surah row with a status control in place of play. No pinch, no zoom.
- Practice presets for the ayah being learned, three buttons with self-describing labels: **Repeat this ayah**, **Listen, then recite**, **Join with previous 2**. They only set the repeat state (§4.4).

## 4. Repeat model

### 4.1 State (single owner: `AudioService.repeatState`, persisted with the session)

| Field | Type / allowed values | Notes |
|---|---|---|
| `isOn` | Bool | false = play through normally |
| `surah` | 1…114 | repeat never spans surahs |
| `from` | 1…ayahCount | |
| `to` | `from`…ayahCount | `from == to` is "one ayah" |
| `times` | 2, 3, 5, 10, or infinite | total plays of the range. There is no "1" |
| `pause` | none, ayahLength, seconds(5), seconds(10) | silence after each ayah, only while `isOn` |
| `completed` | Int, runtime only | passes finished, for "2 of 5" |

Separate, runtime only: `wordRepeat: { ayah, fromWord, toWord }?`. While set, it suspends (does not change) `repeatState`.

Removed: `LoopSettings.Mode`, `PlayerScope`, `SurahDetailViewModel.loopSettings`, the `repeatCount == 0` convention, `listenAndRepeat` + gap as a global setting. Migration: single → from = to; segment → range; count 0 → infinite; 1 → `isOn = false`; 7 → 5; pause-to-repeat on → `ayahLength`.

### 4.2 Every UI string

| Where | String |
|---|---|
| Feature name, sheet title, button label, switch | Repeat |
| Sheet rows | From · To · Times · Pause after each ayah |
| Values | Ayah 3 · 2 · 3 · 5 · 10 · ∞ · None · Ayah length · 5 s · 10 s |
| Sheet shortcuts | This ayah only · Whole surah |
| Sheet buttons | Done · Play ayah 3 · Play ayahs 3–4 |
| Ayah actions | Repeat · Repeat to here · Repeat from here · Stop repeating · More repeat options |
| Word by word | Repeat selected words |
| Now Playing value | Off · Ayah 3 · ∞ · Ayahs 3–4 · 5 times |
| Accessibility value of the Repeat button | "Off" or the status string |

### 4.3 The one status function

`RepeatState.status(current:)` is the only place this text is written; the mini player, Now Playing, Today Recent, the lock screen subtitle and `ListeningSessionStore` all call it (AUDIT #11).

| State | Output |
|---|---|
| Off | "Ayah 255 · Mishary Al-Afasy" |
| One ayah, ∞ | "Repeating ayah 255" |
| Range, ∞ | "Repeating ayahs 255–257" |
| Counted | "Repeating ayahs 255–257 · 2 of 5" |
| Word repeat | "Repeating words 2–4 of ayah 5" |
| Sheet summary | "Ayahs 3–4, 5 times" (+ ", pausing after each") |

### 4.4 Behaviour

| Event | Result |
|---|---|
| Repeat switched on with no range yet | From = To = current ayah (or ayah 1), ∞ |
| Any change in the sheet while playing | Applies at once. If the current ayah is outside the new range, jump to From |
| Any change while paused | State changes; nothing plays until Play |
| End of range, passes remain | Go to From; `completed += 1` |
| Last pass ends | Repeat turns off and playback carries on into the ayah after To |
| Last ayah of a surah ends, Repeat off | Playback continues with ayah 1 of the next surah. After An-Nas it stops |
| Next / Previous ayah with Repeat on | Stay inside the range and wrap |
| User plays an ayah outside the range (reader, ayah bar) | Repeat turns off, playback continues from that ayah |
| Surah changes (new surah played, playback rolls into the next surah) | Repeat turns off |
| Lock screen / CarPlay repeat toggle | Off ↔ current ayah, ∞. Same state, so the app reflects it |
| Reader plays an ayah | `play(surah, ayah)` takes no repeat argument; it reads the service's state (AUDIT #8) |
| Word repeat starts / ends | Main playback pauses / returns paused to the same ayah; `repeatState` untouched |
| Speed change | Independent of Repeat |
| Memorization "Repeat this ayah" | from = to = N, ∞, pause none |
| Memorization "Listen, then recite" | from = to = N, ∞, pause ayahLength |
| Memorization "Join with previous 2" | from = max(1, N−2), to = N, ∞, pause none. One helper, also used by Siri (AUDIT #10) |

## 5. Design tokens

Serif identity stays: display, titles and reading text in the existing serif; controls and metadata in the system sans. All sizes scale with Dynamic Type.

**Type scale**

| Token | Size / weight | Use |
|---|---|---|
| Display | 34 serif regular | tab screen titles, greeting |
| Title | 28 serif | reader and Now Playing surah name |
| Heading | 22 serif | card titles, prayer name |
| Row title | 19 serif (17 in mini player) | list rows |
| Body | 17 | translation, sheet rows, buttons |
| Secondary | 15 | subtitles, metadata, transliteration |
| Caption | 13 semibold | section headings, segmented labels, values |
| Tab label | 11 medium | tab bar labels only |
| Arabic list / Arabic reader | 20 / per `ReadingTypography` (min 26) | |

Rules: 13 pt is the floor for anything read (tab labels excepted). No all-caps with tracking; section headings are sentence case. Italic only for transliteration. Translations are never grey italics.

**Spacing scale:** 4 · 8 · 12 · 16 · 24 · 32 · 48. Screen margin 20. Card padding 16. Section gap 32. No literal spacing values outside the token file.

**Colour roles** (each of the 7 palettes supplies all of them, light and dark)

| Role | Requirement |
|---|---|
| `background` | page |
| `surface` | bars, cards; opaque |
| `surfaceRaised` | sheets, mini player; opaque, no material |
| `textPrimary` | ≥ 7:1 on background and surfaces |
| `textSecondary` | ≥ 4.5:1 |
| `textTertiary` | ≥ 3:1; disabled and decorative only |
| `accent` / `onAccent` | controls, playing state; ≥ 4.5:1 as text, ≥ 3:1 as icon |
| `highlight` | current-ayah background; text on it still ≥ 7:1 |
| `separator` | hairlines |
| `danger` | errors |

**Minimum sizes:** hit target 44 × 44; primary play 56 (list 44, Now Playing 64); surah row 64; More row 56; mini player 56; ayah-action buttons 64 × 64; segmented control height 36 with labels that never truncate (if they don't fit, the control wraps to a menu); horizontal chip rows are not allowed to clip, they wrap or become a menu (AUDIT #17).

**Motion** (via `AnimationKit`; all replaced by a cross-fade under Reduce Motion)

| Token | Value | Use |
|---|---|---|
| quick | 0.15 s ease-out | play ↔ pause symbol, button press |
| standard | 0.25 s ease-in-out | highlight moving between ayahs, row state |
| sheet | spring, response 0.35, damping 0.85 | mini player ↔ Now Playing (shared title), sheets |

No animation may run on a list while it scrolls. No stagger or entrance animations on tab switches.

## 6. AUDIT coverage

| # | Sev | Resolution |
|---|---|---|
| 1 | P0 | Today "Recent" / "Start listening" rows with play buttons |
| 2 | P0 | Play button on every surah row |
| 3 | P1 | App-wide mini player |
| 4 | P1 | Notification prompt deferred to the moment a notification is turned on |
| 5 | P1 | Today playback card removed; one icon rule (icon shows the action, never the state) |
| 6 | P1 | Stop removed; paused player shows play |
| 7 | P0 | One Repeat sheet; expanded-player loop UI deleted |
| 8 | P0 | `AudioService` is the only owner; `play()` takes no loop argument (plan task 1) |
| 9 | P1 | Rows disabled while the switch is off |
| 10 | P1 | Drills are Memorization presets with one range helper |
| 11 | P1 | One status function; "1×" no longer exists |
| 12 | P1 | Word repeat is a visible sub-state that suspends Repeat and shows in the status |
| 13 | P2 | Pause is one row inside Repeat, active only when Repeat is on |
| 14 | P1 | Now Playing: ayah bar, transport, two options |
| 15 | P1 | Ayah actions: 4 buttons + 3 rows, opened by a visible button |
| 16 | P1 | Type floor 13 pt, no tracked caps, contrast roles, tab icons |
| 17 | P1 | No clipped chip rows anywhere |
| 18 | P2 | Fixed nav title; compact title block |
| 19 | P1 | Inline prayer block removed; fixed-height states |
| 20 | P1 | Opaque bars |
| 21 | P1 | Opaque sheets |
| 22 | P2 | Toggle renamed "Hide controls while reading" (one line at all faces) |
| 23 | P2 | One empty state |
| 24 | P2 | Shared bottom inset |
| 25 | P1 | Reader `…` labelled "Reader options"; hidden tab bar removed from accessibility |
| 26 | P2 | Accessibility label = visible text |

## 7. Acceptance checks

Verifiable from screenshots or a UI test on a fresh install unless noted.

**Speed to audio**
1. From a cold launch, tapping the Quran tab then a row's play button starts audio; the screen is still the surah list.
2. From a cold launch with a previous session, a mini player is visible on Today and one tap on its play button resumes audio.
3. On a fresh install, Today shows at least 3 surah rows with play buttons and no blank area taller than 100 pt above the tab bar.
4. Tapping Today's search field lands on the Quran tab with the keyboard up.

**Mini player and state**
5. With a session, the mini player is visible on Today, Quran, More, every More sub-screen and the reader.
6. While paused, every play/pause control on screen shows a play icon; while playing, a pause icon. No screen shows the word "PAUSED".
7. There is no Stop button anywhere.
8. No list's last row is covered by the tab bar or the mini player when scrolled to the end (More shows Settings fully).

**Repeat**
9. Exactly one sheet is titled "Repeat". The strings "Loop", "Reps", "Chain", "Listen" (as a button) and "1×" appear on no screen outside Memorization.
10. With the Repeat switch off, From, To, Times and Pause are dimmed and not tappable.
11. The Repeat sheet has no Cancel and no Apply.
12. Ayah 3 → Repeat, then ayah 4 → "Repeat to here": the mini player reads "Repeating ayahs 3–4" and Now Playing's Repeat value reads "Ayahs 3–4 · ∞".
13. Set a repeat in Now Playing, go to the reader, tap Play on an ayah inside the range: the mini player still reads the same range (regression for AUDIT #8).
14. The same repeat status sentence appears in the mini player, Now Playing and Today Recent, character for character.
15. Now Playing has three control rows (ayah bar, transport, options) and no truncated label.
16. The Repeat sheet and Ayah actions sheet show no reader text through their background.

**Reader and ayah actions**
17. Each ayah has a visible number button; tapping it opens a sheet with exactly four buttons (Play, Repeat, Bookmark, Share) and three rows (Tafsir, Word by word, Add to memorization).
18. The reader's navigation title is the surah name at every scroll position.
19. No two elements in the reader have the accessibility label "More".

**Density, type, wording**
20. No text other than tab labels is smaller than 13 pt; no all-caps letter-spaced label exists.
21. Translation text is upright and uses the primary text colour.
22. The tab bar shows an icon and a label for each of Today, Quran, More.
23. The string "Qur'an" appears nowhere; the Quran tab's title and tab label both read "Quran".
24. No horizontally clipped text or chip on Today, More, Dhikr or the surah list.
25. No control has an explanatory sentence under it.

**Connections**
26. Tapping the Today prayer card opens Prayer Times. Tapping the date opens Islamic Calendar. Tapping the verse of the day text opens the reader.
27. More has no blank block; the Prayer Times row shows a time, "Location needed" or "—".
28. No system permission alert appears during first launch.
29. Scrolling 99 Names, More and the Juz sheet shows no content through the header.

**Swipes and playback flow** (UI test or device, not screenshots)
30. On Today's root, a left swipe shows Quran and another shows More; a vertical scroll never changes tab.
31. In the reader, a right swipe starting at the left edge returns to the list; the same swipe starting mid-screen changes surah.
32. With Repeat set to ayahs 3–4, 2 times: after the second pass ayah 5 plays and the mini player no longer says "Repeating".
33. Letting Al-Faatiha play to the end starts Al-Baqara ayah 1 without a tap.
34. On a device with audio playing, scrolling the reader and opening Now Playing each stay at or above 55 fps in Instruments, with no hitch over 50 ms.

## 8. Implementation plan

Each task is one session and leaves the app shippable. Tasks 1–3 are sequential; task 4 is the lag you reported and stands alone; after that 5 → 6 → 7 → 8 is the critical path and the rest are independent.

| # | Task | Files likely touched | Done when |
|---|---|---|---|
| 1 | **Unify loop state (AUDIT #8).** Delete `SurahDetailViewModel.loopSettings`; `play()` stops taking settings; the Repeat sheet and reader read `AudioService.loopSettings`. No UI change. | `ViewModels/SurahDetailViewModel.swift` (112–123), `Views/SurahDetailView.swift`, `AudioService`, LoopSettings sheet | Check 13 passes; a unit test sets a loop on the service, plays from the view model, state unchanged |
| 2 | **Introduce `RepeatState`** (§4.1) replacing `LoopSettings.Mode` and `PlayerScope`, with migration, the status function and the "previous 2" helper. Engine behaviours from §4.4. Old UIs adapted minimally. | `LoopSettings` model, `AudioService`, `QuranPlayerView` (:78), `HomeListeningCards` (:208), `ListeningSessionStore` (:31), CarPlay and Siri intent files | Unit tests for every row of §4.4; one status function, three call sites |
| 3 | **One Repeat sheet** (§3.6). Delete the expanded player's scope/reps/range rows, the mini-bar cycle and the sheet's presets. | LoopSettings sheet view, `QuranPlayerView` (`QuranPlayerBar`, `QuranExpandedPlayer`), `EditorialControls.swift` | Checks 9–11, 16 |
| 4 | **Frame rate while audio plays.** See `docs/audit/BUGS.md` → "Performance while audio plays". The per-tick playhead is already split out (`PlaybackClock`), so ticks are not the cause. Profile on a device first, then address the three reading-based suspects in order: (1) every audio state change rebuilds all realised ayah rows, because each row gets fresh closures and cannot be skipped; (2) perpetual animations while playing (`PlayingIndicatorView`, the scrubber re-animating every 0.1 s) inside a material bar; (3) expanding the player re-evaluates the 114-page pager inside a spring animation. | `Views/SurahDetailView.swift`, `AyahRowView.swift`, `QuranPlayerView.swift`, `AnimationKit.swift` | Check 34, with before/after numbers |
| 5 | **Tokens.** Add spacing, type and colour-role tokens; opaque bar and sheet backgrounds; replace `Eyebrow`/`MetaText` styles; tab bar icons. | `DesignSystem.swift`, `AppTheme.swift`, `ReadingTypography.swift`, `EditorialTabBar` | Checks 20–22, 29; contrast table for all 7 palettes |
| 6 | **App-wide mini player** (§3.4) at the root with the shared bottom inset; restore the paused session at launch; delete `HomeMiniPlayer` and Stop. | `Quran_AppApp.swift`, `QuranPlayerView`, `Views/HomeView.swift`, `ListeningSessionStore`, `AudioService` | Checks 2, 5–8 |
| 7 | **Surah row with play** (§3.2), filter menu, Juz row play, row states. | `Views/SurahListView.swift`, Juz sheet view, `DesignSystem.swift` (`PlayCircle`) | Checks 1, 23 |
| 8 | **Today rebuild** (§3.1), reusing the row from task 7. | `Views/HomeView.swift`, `HomeListeningCards`, `PrayerTimesService` (read only) | Checks 3, 4, 26 |
| 9 | **Now Playing rebuild** (§3.5) as a sheet with the ayah bar. | `QuranPlayerView` (`QuranExpandedPlayer`), `Views/SurahDetailView.swift` (overlay removal), `AnimationKit.swift` | Checks 12, 15 |
| 10 | **Reader header + Ayah actions sheet** (§3.3, §3.7). Split `SurahDetailView.swift` into header, ayah row, actions sheet and sheet routing while doing it. | `Views/SurahDetailView.swift` and new files beside it | Checks 17–19 |
| 11 | **Word repeat** inside Word by word; delete `WordLoopPicker`; merge `ClipPlayer`/`GapClipPlayer`. | `WordLoopPicker`, word-by-word view, `AudioService`, `ClipPlayer`, `GapClipPlayer` | Status reads "Repeating words…"; main repeat restored after |
| 12 | **More + Prayer Times** (§3.8); defer the notification prompt. | `Views/MoreView.swift`, prayer times view, `PrayerTimesService`, notification setup, `Quran_AppApp.swift` | Checks 8, 27, 28 |
| 13 | **Memorization** (§3.9): presets, single empty state, grid → grouped list. | Memorization views, `MemorizationStore`, Siri intent | No pinch gesture; presets produce the §4.4 states |
| 14 | **Wording and accessibility pass**: §2 vocabulary, labels equal visible text, remove explanatory captions; update the `QuranTour` UI test to assert the §7 checks. | all views (strings only), `QuranTourUITests` | Checks 9, 19, 23, 25; tour reaches Settings and Calendar |
| 15 | **Swipe navigation** (§3.0): tab swiping on the three roots, 32 pt back zone and surah paging in the reader, one shared gesture threshold. | `Quran_AppApp.swift`, `EditorialTabBar`, `Views/SurahDetailView.swift` (pager), `AnimationKit.swift` | Checks 30, 31 |
| 16 | **Motion pass**: the three motion tokens, mini player ↔ Now Playing transition, ayah highlight, Reduce Motion. | `AnimationKit.swift`, player and reader views | No animation without a token |
| 17 | **Dead code and remaining performance**: lazy stacks where profiling shows a need; remove `SectionHeader`, `GoalBadge`, `QuranWidgetControl`, the `build/` folder, the debug print in `PrayerLiveActivityService:75`. | as profiled | Before/after numbers recorded in the PR |

## 9. Decisions and open questions

**Decided by you (2026-11-09)**
- A counted repeat that finishes carries on into the next ayah, and a finished surah carries on into the next surah (§4.4).
- Pause options stay None / Ayah length / 5 s / 10 s.
- Tabs swipe on the three root screens; in the reader the left 32 pt goes back and the rest changes surah (§3.0).
- The reader has no top-bar Repeat button.
- The mini player is restored paused at launch.
- The ayah bar replaces the time scrubber.
- A tap on a word still plays the word; Ayah actions open from the number button or long-press.
- Lag is worst while audio plays and when opening the player: plan task 4.

**Still open**
1. **Memorization grid.** I have not seen it; it is replaced by a status-grouped list. Is anything about the grid worth keeping, such as the at-a-glance 114-cell overview?
2. **Juz 30 on Today.** It moved to Quran → Juz (3 taps). If you play it often it could be pinned as a Recent-style row.
3. **Juz playback.** With surahs now rolling into the next surah, "play Juz 30" is simply "start at An-Naba and keep going". Should it stop at the end of the juz, or is that enough?
4. **Not covered by the audit and therefore not designed here:** dark mode, largest Dynamic Type sizes, landscape, CarPlay screens, widgets, Settings layout, onboarding.
