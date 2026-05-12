import CarPlay
import UIKit
import Combine

@MainActor
final class CarPlayTemplateManager: NSObject {

    // MARK: - Dependencies
    private var audio: AudioService?     { CarPlayBridge.shared.audioService }
    private var memory: MemorizationStore? { CarPlayBridge.shared.memorizationStore }

    // MARK: - State
    private weak var controller: CPInterfaceController?
    private var surahs: [Surah] = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func connect(to controller: CPInterfaceController) {
        self.controller = controller

        // CarPlay requires a root template synchronously — set a spinner immediately.
        let loading = CPListTemplate(title: "Quran", sections: [
            CPListSection(items: [CPListItem(text: "Loading…", detailText: nil)])
        ])
        controller.setRootTemplate(loading, animated: false, completion: nil)

        observeAudio()
        Task { await loadSurahs() }
    }

    func disconnect() {
        cancellables.removeAll()
    }

    // MARK: - Data

    private func loadSurahs() async {
        do { surahs = try await QuranAPIService.shared.fetchSurahList() }
        catch { surahs = [] }
        buildRoot()
    }

    // MARK: - Root template

    private func buildRoot() {
        let memorized  = memorizedTemplate()
        let browse     = browseTemplate()
        let nowPlaying = nowPlayingTemplate()

        let tabs = CPTabBarTemplate(templates: [memorized, browse, nowPlaying])
        controller?.setRootTemplate(tabs, animated: true, completion: nil)
    }

    // MARK: - Memorized tab

    private func memorizedTemplate() -> CPListTemplate {
        let memorizedSurahs = surahs.filter {
            memory?.status(for: $0.number) == .memorized
        }

        let items: [CPListItem] = memorizedSurahs.isEmpty
            ? [CPListItem(text: "No memorized surahs yet",
                          detailText: "Mark surahs in the app")]
            : memorizedSurahs.map { surah in
                let item = CPListItem(
                    text: surah.englishName,
                    detailText: "\(surah.name)  ·  \(surah.numberOfAyahs) ayahs"
                )
                item.handler = { [weak self] _, done in
                    Task { @MainActor [weak self] in
                        self?.playSurah(surah)
                        done()
                    }
                }
                return item
            }

        let t = CPListTemplate(title: "Memorized",
                               sections: [CPListSection(items: items)])
        t.tabImage = UIImage(systemName: "star.fill")
        return t
    }

    // MARK: - Browse tab (Juz → Surah)

    private func browseTemplate() -> CPListTemplate {
        let items: [CPListItem] = (1...30).map { juz in
            let item = CPListItem(text: "Juz \(juz)",
                                  detailText: juzSubtitle(juz))
            item.handler = { [weak self] _, done in
                Task { @MainActor [weak self] in
                    self?.pushSurahList(forJuz: juz)
                    done()
                }
            }
            return item
        }
        let t = CPListTemplate(title: "All Surahs",
                               sections: [CPListSection(items: items)])
        t.tabImage = UIImage(systemName: "book.fill")
        return t
    }

    private func pushSurahList(forJuz juz: Int) {
        let numbers      = JuzData.surahNumbers(inJuz: juz)
        let surahsInJuz  = surahs.filter { numbers.contains($0.number) }

        let items: [CPListItem] = surahsInJuz.map { surah in
            let item = CPListItem(
                text: surah.englishName,
                detailText: "\(surah.name)  ·  \(surah.numberOfAyahs) ayahs"
            )
            item.handler = { [weak self] _, done in
                Task { @MainActor [weak self] in
                    self?.playSurah(surah)
                    self?.controller?.popTemplate(animated: true, completion: nil)
                    done()
                }
            }
            return item
        }
        let t = CPListTemplate(title: "Juz \(juz)",
                               sections: [CPListSection(items: items)])
        controller?.pushTemplate(t, animated: true, completion: nil)
    }

    // MARK: - Now Playing tab

    private func nowPlayingTemplate() -> CPNowPlayingTemplate {
        let t = CPNowPlayingTemplate.shared
        t.tabImage = UIImage(systemName: "music.note")
        updateNowPlayingButtons()
        return t
    }

    private func updateNowPlayingButtons() {
        let isLooping = audio?.loopSettings.mode == .single
        let repeatBtn = CPNowPlayingRepeatButton { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currently = self.audio?.loopSettings.mode == .single
                self.audio?.setLoopSingleAyah(!currently)
                self.updateNowPlayingButtons()
            }
        }
        // Show repeat-1 icon when looping, plain repeat when off
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(
            isLooping ? [repeatBtn] : [repeatBtn]   // same button; system reflects MPRemoteCommand state
        )
    }

    // MARK: - Playback

    private func playSurah(_ surah: Surah) {
        audio?.play(
            surah: surah.number,
            startAyah: 1,
            loop: LoopSettings(mode: .off, startAyah: 1,
                               endAyah: surah.numberOfAyahs, repeatCount: 0),
            totalAyahs: surah.numberOfAyahs,
            surahName: surah.englishName
        )
    }

    // MARK: - Audio observation (now-playing info)

    private func observeAudio() {
        guard let audio else { return }

        Publishers.CombineLatest(audio.$currentAyah, audio.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.audio?.updateNowPlayingInfo()
                }
            }
            .store(in: &cancellables)

        audio.$loopSettings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateNowPlayingButtons() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Helpers

    private func juzSubtitle(_ juz: Int) -> String {
        guard let b = JuzData.boundary(for: juz) else { return "" }
        let start = surahs.first { $0.number == b.startSurah }?.englishName ?? "Surah \(b.startSurah)"
        let end   = surahs.first { $0.number == b.endSurah   }?.englishName ?? "Surah \(b.endSurah)"
        return start == end ? start : "\(start) – \(end)"
    }
}
