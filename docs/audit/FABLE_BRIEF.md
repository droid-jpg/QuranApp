# Prompt for the Fable redesign session

Start a **new session** in this folder, choose Fable, and paste everything below the line. Fill in "My pain points" first. Attach only `docs/audit/key-screens-01.jpg`.

---

You are redesigning the UX of my SwiftUI Quran app. **This is a design-only task.** Do not explore the repo, read Swift files, build, run the simulator or take screenshots: everything you need is in the files listed below. If something is genuinely missing, list it as an open question instead of investigating.

Read, in order:
1. `docs/audit/AUDIT.md`: 26 ranked issues from a scripted walkthrough.
2. `docs/audit/ARCHITECTURE.md`: screens, playback paths, the 7 loop concepts, settings, the design system.
3. The attached `key-screens-01.jpg`: Today, Today while playing, the surah list, the reader, the ayah menu, the Repeat sheet, the expanded player, More.

**My pain points:**
- (too much text crammed into small places)
- (it takes too long to get from opening the app to hearing a surah)
- (I don't understand the different loop types)
- Functions that feel like they should be connected aren't. For example, prayer times on the Today screen. If i click it, nothing happens so I have to go to More then Prayer Times to see more.
- Again, lack of functions that make the app feel more fluid and easier to use, like swiping between screens but reducing accidental swipes
- Lack of animations or dysfunctional animations
- Memorization grid is very hard to use, pinch through, etc.
- App phrasing is confusing all around. If a feature needs explanation under it, then rethink it.
- Using the app feels slow, both traversing menus and lag in general. Feels bloated and needs to be cut down.
- Visual bugs, like bottom bars cutting over the content
- (what I use most: looping between two ayahs within a surah, reading)
- (what I never use: the memorization engine)

**Goals, in priority order:**
1. Cold launch → hearing any surah in **≤ 2 taps** (plus search), and resuming last playback in **1 tap**.
2. **One** repeat/loop model with one UI and one source of truth, understandable without reading. Decide what happens to Listen/Repeat/Chain, Pause-to-repeat and Word loop (keep, fold in, or move to Memorization only).
3. Less dense screens: fewer control rows, real type sizes (no tiny letter-spaced caps for anything a user must read), and enough contrast.
4. Fix every P0/P1 item in AUDIT.md, either through the new design or as an explicit fix.
5. Keep the existing features and the editorial, serif visual identity unless you justify dropping something.
6. UI consistency. For example, no two screens should have different spelling for the same term (e.g. Quran and Qur'an)

**Write `docs/REDESIGN.md` containing:**
- **Information architecture**: tabs and screens, and where every current feature now lives (table: feature → new location).
- **Screen specs** for Today, Surah list, Reader, Mini player (app-wide?), Now Playing, the Repeat control, the Ayah actions, and More. For each: purpose, layout top to bottom, controls with exact labels, states (empty, loading, playing, error).
- **Repeat model**: the state shape (fields and allowed values), every UI string, and a short behaviour table.
- **Design tokens**: type scale, spacing scale, colour roles, minimum sizes.
- **Acceptance checks**: testable statements a cheaper model can verify from screenshots (e.g. "Surah list row has a play button; tapping it starts audio without leaving the list").
- **Implementation plan**: ordered tasks, each independent where possible, naming the files likely touched (use ARCHITECTURE.md), sized for one session each. Put the loop-state unification (AUDIT #8) first.
- **Open questions** for me.

Be decisive and concise. One pass, no code.
