# App Store submission sheet

Everything App Store Connect asks for, filled in for this app. Copy from here when creating the listing.

## Before you upload

1. **Bundle ID.** The app is `sami.Quran-App` (widget `sami.Quran-App.QuranWidget`), and the App Group is
   `group.com.saminukta.Quran-App`. These work as they are. If you would rather ship under a `com.` prefix, change
   it now: once the app is on the store the bundle ID can never change.
2. **Test on a real iPhone.** Background playback on a locked phone, the lock-screen and Control Center controls,
   the Qibla compass and the lock-screen widget have only been run in the simulator. Install a build through
   TestFlight and try each one before submitting.
3. **Archive.** In Xcode: scheme **Quran App**, destination **Any iOS Device**, Product › Archive, then Distribute
   App › App Store Connect. Raise `CURRENT_PROJECT_VERSION` (the build number) for every new upload.
4. **Push `PRIVACY.md`** to `main` on GitHub before submitting. The app and the listing link to it.

## Listing

| Field | Value |
|---|---|
| Name (30 max) | The name "Quran" is almost certainly taken. Suggestions: **Quran: Read & Listen**, **Quran · Recite & Repeat** |
| Subtitle (30 max) | Read, listen, repeat, pray |
| Primary category | Reference |
| Secondary category | Lifestyle |
| Price | Free |
| Privacy Policy URL | https://github.com/droid-jpg/QuranApp/blob/main/PRIVACY.md |
| Support URL | https://github.com/droid-jpg/QuranApp/issues |
| Copyright | 2026 (your name) |

**Keywords (100 max):**
`quran,koran,quran audio,recitation,tafsir,prayer times,salah,qibla,islam,muslim,surah,ayah,dhikr,hifz`

**Promotional text (170 max):**
Read and listen to the whole Quran, follow each word as it is recited, and repeat any stretch of ayahs until it
stays with you.

**Description:**

> A calm, focused way to read and listen to the Quran.
>
> READ
> • All 114 surahs and the 30 juz, with Arabic, transliteration and translation
> • The full text is built in, so reading works with no connection
> • Translations in 20 languages, downloaded once and kept
> • Adjustable typeface, Arabic script style and text sizes
>
> LISTEN
> • Seven renowned reciters
> • The word being recited is highlighted as it is said
> • Four playback speeds, and an optional pause after each ayah to recite it back
> • Everything you play is saved for offline listening, or download whole surahs ahead of time
>
> REPEAT
> • Tap two ayahs and everything between them repeats, as many times as you choose
> • Repeat a stretch of words inside a single ayah
>
> EVERY AYAH
> • Word by word meanings and transliteration
> • Tafsir Ibn Kathir (abridged)
> • Bookmark, share and copy
>
> EVERY DAY
> • Prayer times with notifications, and a lock-screen widget for the next prayer
> • Qibla compass
> • Islamic calendar with the year's important dates
> • Dhikr counter and flashcards for the 99 Names of Allah
>
> No accounts, no ads, no tracking.

## App Privacy (the "nutrition label")

Answer **Yes, we collect data**, then:

| Data type | Collected | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|---|
| Location › Coarse Location | Yes | No | No | App Functionality |

Nothing else is collected. (A rounded position goes to AlAdhan to fetch prayer times. All other data stays on the
device.) This matches `Quran App/PrivacyInfo.xcprivacy`.

## Age rating

Answer **None** to every content question. No web browsing, no user-generated content, no gambling, no contests.
The result is **4+**.

## Export compliance

`ITSAppUsesNonExemptEncryption` is set to `NO` in Info.plist: the app only uses HTTPS, which is exempt. App Store
Connect will not ask the question.

## Screenshots

Required: **6.9-inch iPhone** (1320 × 2868 or 1290 × 2796), 3 to 10 of them. The app is iPhone-only, so no iPad
screenshots are needed. The **QuranTour** UI tests save a screenshot of every screen when
`TEST_RUNNER_SHOTS_DIR` is set: run them on an iPhone 17 Pro Max simulator to get the right size. Suggested order:
Reader with the recited word highlighted, Now Playing, Repeat range, Word by word, Today, Prayer Times, Qibla.

## Notes for the reviewer

> No sign-in is needed. Location is optional and is only used for prayer times and the Qibla direction; every other
> feature works without it. To try the main features: open the Quran tab, tap the play button on any surah, then
> tap two ayahs in the reader to repeat the range between them. Audio, word timings and tafsir are fetched from
> quran.com on first use and kept on the device.

## Content rights

App Store Connect asks whether the app uses third-party content. Answer **Yes** and that you have the rights to use
it. The bundled text is Tanzil (CC BY 3.0, credited and linked in Settings › Sources) with Pickthall's
public-domain translation. Audio, tafsir and the other translations are fetched at runtime from the public
quran.com, alquran.cloud and EveryAyah services, which many Quran apps use. Some of the optional translations
(for example Saheeh International and The Clear Quran) are copyrighted by their publishers; if you want to be
strict, remove them from `Models/Translation.swift` or ask their publishers for permission.
