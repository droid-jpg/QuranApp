import SwiftUI
import UIKit
import Combine

// Swipe navigation (REDESIGN §3.0). One rule for every horizontal swipe, in one
// place: it starts only after 12 pt of travel at least twice as horizontal as
// vertical, follows the finger, and commits past 40% of the width or on a flick;
// otherwise it springs back. Vertical scrolling never triggers it.
//
// The recognizers are UIKit ones installed on the screen's own view controller,
// so the decision to start is made before any SwiftUI gesture or scroll view
// claims the touch, and the per-frame offset lives in a small observable that
// only the view applying it reads: a drag never re-evaluates tab contents, the
// reader's pages or its ayah rows.

// MARK: - The rule

enum SwipeRule {
    /// Travel before a swipe can start.
    static let activation: CGFloat = 12
    /// How much more horizontal than vertical that travel must be.
    static let dominance: CGFloat = 2
    /// Share of the width past which a release commits.
    static let commitFraction: CGFloat = 0.4
    /// A release at least this fast (pt/s) in the swipe's direction commits.
    static let flickVelocity: CGFloat = 500
    /// The left strip where a right swipe means Back, not "change surah".
    static let backZone: CGFloat = 32
    /// How far a swipe follows the finger when there is nothing to go to.
    static let resistance: CGFloat = 0.25

    /// Whether a released swipe goes to the neighbour.
    static func commits(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard translation != 0, width > 0 else { return false }
        let direction: CGFloat = translation > 0 ? 1 : -1
        let along = velocity * direction
        if along >= flickVelocity { return true }
        return abs(translation) >= width * commitFraction && along > -flickVelocity
    }

    /// The same idea upright, for the mini player's swipe up: 12 pt at 2:1
    /// vertical, then a release past 32 pt up or an upward flick.
    static func commitsUp(translation: CGSize, velocity: CGSize) -> Bool {
        let dy = -translation.height
        guard dy >= activation, dy >= abs(translation.width) * dominance else { return false }
        return dy >= Spacing.xl || -velocity.height >= flickVelocity
    }

    /// The offset a drag is drawn at: one to one, or with resistance when there
    /// is no neighbour that way.
    static func follow(_ translation: CGFloat, canGo: Bool) -> CGFloat {
        canGo ? translation : translation * resistance
    }
}

// MARK: - Recognizer

/// A one-finger horizontal pan that applies `SwipeRule` before it begins: it
/// fails as soon as the first 12 pt are not at least twice as horizontal as
/// vertical, so a scroll view keeps every vertical or diagonal drag.
final class HorizontalSwipeRecognizer: UIGestureRecognizer {
    /// Asked at touch-down with the touch's location in the window.
    var canStart: (CGPoint) -> Bool = { _ in true }

    /// Horizontal travel since touch-down (+ is to the right).
    private(set) var translation: CGFloat = 0
    /// Horizontal velocity at release, pt/s.
    private(set) var velocity: CGFloat = 0

    private var start: CGPoint = .zero
    private var samples: [(time: TimeInterval, x: CGFloat)] = []

    /// Pans inside the swiped view (a list's or a scroll view's own pan) wait
    /// the first 12 pt for this one to decide. A list's pan otherwise claims a
    /// horizontal drag too, though it can only scroll vertically.
    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        guard other is UIPanGestureRecognizer, !(other is HorizontalSwipeRecognizer),
              let mine = view, let theirs = other.view, theirs !== mine
        else { return false }
        return theirs.isDescendant(of: mine)
    }

    /// SwiftUI's own touch recognizer (behind buttons and tap gestures) begins
    /// at touch-down; it must not shut this one out, or no swipe could start
    /// on a card or a row. Once this one begins it cancels those recognizers
    /// (`cancelTaps(under:)`), so the button under the finger doesn't fire.
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer ? super.canBePrevented(by: other) : false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, numberOfTouches <= 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled
            return
        }
        start = touch.location(in: nil)
        samples = [(touch.timestamp, start.x)]
        if !canStart(start) { state = .failed }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let p = touch.location(in: nil)
        let dx = p.x - start.x, dy = p.y - start.y
        samples.append((touch.timestamp, p.x))
        if samples.count > 6 { samples.removeFirst(samples.count - 6) }

        switch state {
        case .possible:
            guard hypot(dx, dy) >= SwipeRule.activation else { return }
            if abs(dx) >= abs(dy) * SwipeRule.dominance {
                translation = dx
                state = .began
                cancelTaps(under: touch)
            } else {
                state = .failed
            }
        case .began, .changed:
            translation = dx
            state = .changed
        default:
            break
        }
    }

    /// A swipe has begun: every other recognizer tracking this finger (SwiftUI's
    /// button and tap recognizers, which run alongside this one) is cancelled by
    /// switching it off and on, so lifting the finger doesn't press the button
    /// it started on. `cancelsTouchesInView` alone doesn't reach them. Scroll
    /// views' pans and the navigation controller's Back pans are left alone:
    /// they already wait for this one or own their own region.
    private func cancelTaps(under touch: UITouch) {
        for other in touch.gestureRecognizers ?? [] where other !== self {
            if other is HorizontalSwipeRecognizer || other is UIScreenEdgePanGestureRecognizer { continue }
            if other is UIPanGestureRecognizer, other.view is UIScrollView || other.delegate is EdgeBackDelegate
                || other.view is UINavigationBar { continue }
            if other.view?.next is UINavigationController { continue }
            guard other.isEnabled else { continue }
            other.isEnabled = false
            other.isEnabled = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if state == .began || state == .changed {
            if let touch = touches.first {
                let p = touch.location(in: nil)
                translation = p.x - start.x
                // A lift where the last move left off adds no speed sample
                // (unless the finger rested there a while), or it reads as zero.
                let restedAtLastMove = samples.last.map { $0.x == p.x && touch.timestamp - $0.time < 0.05 } ?? false
                if !restedAtLastMove { samples.append((touch.timestamp, p.x)) }
            }
            velocity = Self.velocity(of: samples)
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        velocity = 0
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        translation = 0
        velocity = 0
        samples = []
    }

    /// From the last sample and the newest one at least 10 ms older, within
    /// 150 ms, so a finger that stopped before lifting is not read as a flick
    /// and moves delivered together still give a speed.
    private static func velocity(of samples: [(time: TimeInterval, x: CGFloat)]) -> CGFloat {
        guard let last = samples.last,
              let earlier = samples.last(where: { last.time - $0.time >= 0.01 }),
              last.time - earlier.time <= 0.15
        else { return 0 }
        return (last.x - earlier.x) / CGFloat(last.time - earlier.time)
    }
}

// MARK: - Keyboard

/// Whether the software keyboard is on screen. Tab swiping is off while it is.
@MainActor
final class KeyboardPresence {
    static let shared = KeyboardPresence()
    private(set) var isVisible = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                        object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyboardPresence.shared.isVisible = true }
        })
        observers.append(nc.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                        object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyboardPresence.shared.isVisible = false }
        })
    }

    /// Starts listening; called once at launch.
    func start() {}
}

// MARK: - Tabs

extension Notification.Name {
    /// Asks the root to select the tab in `object` (an `AppTab`).
    static let selectAppTab = Notification.Name("selectAppTab")
}

/// How far the tabs are being dragged. Observed only by `TabSwipeStage`.
@MainActor
final class TabSwipe: ObservableObject {
    static let shared = TabSwipe()
    @Published var offset: CGFloat = 0
    /// A committed swipe is settling; a new one waits for it.
    var settling = false
    /// Now Playing covers the tabs (set by `PlayerUI`).
    var blocked = false
    private init() {}

    func neighbour(of tab: AppTab, translation: CGFloat) -> AppTab? {
        let all = AppTab.allCases
        guard let i = all.firstIndex(of: tab) else { return nil }
        // Finger to the left shows the tab to the right, as a pager would.
        let j = translation < 0 ? i + 1 : i - 1
        return all.indices.contains(j) ? all[j] : nil
    }

    func changed(tab: AppTab, translation: CGFloat) {
        offset = SwipeRule.follow(translation, canGo: neighbour(of: tab, translation: translation) != nil)
    }

    func ended(tab: AppTab, translation: CGFloat, velocity: CGFloat, width: CGFloat) {
        guard let target = neighbour(of: tab, translation: translation),
              SwipeRule.commits(translation: translation, velocity: velocity, width: width)
        else {
            withAnimation(Motion.sheet) { offset = 0 }
            return
        }
        Haptics.selection()
        settling = true
        // The new tab takes the place a pager would have drawn it at, beside the
        // finger, then settles. The old tab, already mostly off screen, goes.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            offset = translation + (translation < 0 ? width : -width)
            NotificationCenter.default.post(name: .selectAppTab, object: target)
        }
        DispatchQueue.main.async {
            withAnimation(Motion.sheet, completionCriteria: .logicallyComplete) {
                self.offset = 0
            } completion: {
                self.settling = false
            }
        }
    }

    func cancelled() {
        withAnimation(Motion.sheet) { offset = 0 }
    }
}

/// Draws the tabs at the swipe's offset. The tabs are built by the root and
/// handed in, so a frame of the drag re-runs only this body.
struct TabSwipeStage<Content: View>: View {
    @ObservedObject private var swipe = TabSwipe.shared
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.offset(x: swipe.offset)
    }
}

extension View {
    /// On this tab's root screen, a left or right swipe anywhere moves to the
    /// adjacent tab. Applied once per tab, around its NavigationStack; off on a
    /// pushed screen, with the keyboard up, under a sheet or Now Playing.
    func swipesBetweenTabs(_ tab: AppTab) -> some View {
        background(TabSwipeInstaller(tab: tab).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Puts the recognizer on the tab's own view controller (the child of the tab
/// bar controller), where it sees every touch in the tab.
private struct TabSwipeInstaller: UIViewControllerRepresentable {
    let tab: AppTab

    func makeUIViewController(context: Context) -> Controller { Controller(tab: tab) }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        let appTab: AppTab
        private let recognizer = HorizontalSwipeRecognizer()
        private weak var tabRoot: UIViewController?

        init(tab: AppTab) {
            self.appTab = tab
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        private func install() {
            var vc: UIViewController? = parent
            while let current = vc, !(current.parent is UITabBarController) { vc = current.parent }
            guard let root = vc, root !== tabRoot else { return }
            tabRoot = root
            recognizer.view?.removeGestureRecognizer(recognizer)
            recognizer.addTarget(self, action: #selector(handle(_:)))
            recognizer.canStart = { [weak self] _ in self?.mayStart ?? false }
            root.view.addGestureRecognizer(recognizer)
        }

        /// Only on the tab's root screen, with nothing over it.
        private var mayStart: Bool {
            guard let root = tabRoot, !TabSwipe.shared.settling, !TabSwipe.shared.blocked,
                  !KeyboardPresence.shared.isVisible,
                  root.presentedViewController == nil,
                  let nav = Self.navigationController(in: root),
                  nav.viewControllers.count <= 1,
                  nav.transitionCoordinator == nil
            else { return false }
            return true
        }

        private static func navigationController(in vc: UIViewController) -> UINavigationController? {
            if let nav = vc as? UINavigationController { return nav }
            for child in vc.children {
                if let nav = navigationController(in: child) { return nav }
            }
            return nil
        }

        @objc private func handle(_ r: HorizontalSwipeRecognizer) {
            let swipe = TabSwipe.shared
            switch r.state {
            case .began, .changed:
                swipe.changed(tab: appTab, translation: r.translation)
            case .ended:
                swipe.ended(tab: appTab, translation: r.translation, velocity: r.velocity,
                            width: r.view?.bounds.width ?? 1)
            case .cancelled, .failed:
                swipe.cancelled()
            default:
                break
            }
        }
    }
}

// MARK: - Reader

/// The reader pager's drag. Observed only by `ReaderPagerTrack`.
@MainActor
final class ReaderPagerDrag: ObservableObject {
    @Published var offset: CGFloat = 0
    /// A committed swipe is settling; the next one waits, so a flick moves one surah.
    var settling = false
}

/// Places each page one width from its neighbour around `current`. Pages carry
/// their index as a layout value.
struct PagerLayout: Layout {
    var current: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for page in subviews {
            let i = page[PageIndexKey.self]
            page.place(at: CGPoint(x: bounds.minX + CGFloat(i - current) * bounds.width, y: bounds.minY),
                       anchor: .topLeading,
                       proposal: ProposedViewSize(bounds.size))
        }
    }
}

nonisolated struct PageIndexKey: LayoutValueKey {
    static let defaultValue = 0
}

/// Draws the pages at the drag's offset. The pages are built by the pager and
/// handed in, so a frame of the drag re-runs only this body.
struct ReaderPagerTrack<Content: View>: View {
    @ObservedObject var drag: ReaderPagerDrag
    let content: Content

    init(drag: ReaderPagerDrag, @ViewBuilder content: () -> Content) {
        self.drag = drag
        self.content = content()
    }

    var body: some View {
        content.offset(x: drag.offset)
    }
}

/// The reader's two horizontal gestures, split at the left 32 pt:
/// - a right swipe starting inside it is the navigation controller's own
///   interactive Back, which the hidden bar had switched off;
/// - a swipe starting outside it pages to the previous or next surah.
struct ReaderSwipeInstaller: UIViewControllerRepresentable {
    let drag: ReaderPagerDrag
    /// Whether there is a surah that way (-1 previous, +1 next).
    let canPage: (Int) -> Bool
    /// Moves to the surah that way, once the page has slid into place.
    let onPage: (Int) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.drag = drag
        controller.canPage = canPage
        controller.onPage = onPage
    }

    final class Controller: UIViewController {
        var drag: ReaderPagerDrag?
        var canPage: (Int) -> Bool = { _ in false }
        var onPage: (Int) -> Void = { _ in }

        private let recognizer = HorizontalSwipeRecognizer()
        private weak var page: UIViewController?
        /// Back from the left 32 pt (`BackStripPan`), on the navigation
        /// controller's view while the reader is on screen.
        private let backPan = BackStripPan()
        private let edgeDelegate = EdgeBackDelegate()
        /// The edge Back pan's own delegate, put back when the reader goes.
        private var savedEdgeDelegate: (UIGestureRecognizer, UIGestureRecognizerDelegate?)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            installPager()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            installPager()
            enableBack()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableBack()
        }

        /// Not in `viewWillDisappear`: that runs as an interactive pop *starts*,
        /// and removing the Back pan then cancels it mid-gesture and strands the
        /// transition. A cancelled pop calls `viewDidAppear` again instead.
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restoreBack()
        }

        /// The screen the navigation controller pushed.
        private var pushed: UIViewController? {
            var vc: UIViewController? = parent
            while let current = vc, !(current.parent is UINavigationController) { vc = current.parent }
            return vc
        }

        private func installPager() {
            guard let screen = pushed, screen !== page else { return }
            page = screen
            recognizer.view?.removeGestureRecognizer(recognizer)
            recognizer.addTarget(self, action: #selector(handle(_:)))
            recognizer.canStart = { [weak self] point in
                guard let self, let drag = self.drag, !drag.settling else { return false }
                // The left strip belongs to Back.
                return point.x > SwipeRule.backZone
            }
            screen.view.addGestureRecognizer(recognizer)
        }

        /// With the system bar hidden, UIKit's own Back pans don't start 32 pt in:
        /// the screen-edge pan starts only at the very edge (kept, with a delegate
        /// that allows it while the bar is hidden), and the content-area pan not
        /// at all. `BackStripPan` covers the strip and drives the same
        /// interactive pop.
        private func enableBack() {
            guard savedEdgeDelegate == nil, let nav = pushed?.navigationController else { return }
            edgeDelegate.nav = nav
            if let edge = nav.interactivePopGestureRecognizer {
                savedEdgeDelegate = (edge, edge.delegate)
                backPan.install(on: nav, driver: edge.delegate)
                edge.delegate = edgeDelegate
                edge.isEnabled = true
            }
        }

        private func restoreBack() {
            if let (edge, delegate) = savedEdgeDelegate { edge.delegate = delegate }
            savedEdgeDelegate = nil
            backPan.uninstall()
        }

        @objc private func handle(_ r: HorizontalSwipeRecognizer) {
            guard let drag else { return }
            let t = r.translation
            // Finger to the left is the next surah, as the old page view had it.
            let direction = t < 0 ? 1 : -1
            switch r.state {
            case .began, .changed:
                drag.offset = SwipeRule.follow(t, canGo: canPage(direction))
            case .ended:
                let width = r.view?.bounds.width ?? 1
                guard canPage(direction),
                      SwipeRule.commits(translation: t, velocity: r.velocity, width: width)
                else {
                    withAnimation(Motion.sheet) { drag.offset = 0 }
                    return
                }
                Haptics.selection()
                drag.settling = true
                withAnimation(Motion.sheet, completionCriteria: .logicallyComplete) {
                    drag.offset = direction > 0 ? -width : width
                } completion: { [weak self] in
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) {
                        self?.onPage(direction)
                        drag.offset = 0
                    }
                    drag.settling = false
                }
            default:
                withAnimation(Motion.sheet) { drag.offset = 0 }
            }
        }
    }
}

/// The navigation controller's screen-edge Back pan, allowed with the bar hidden
/// and only rightward.
private final class EdgeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var nav: UINavigationController?

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let nav, nav.viewControllers.count > 1, nav.transitionCoordinator == nil else { return false }
        if let pan = g as? UIPanGestureRecognizer {
            // This pan asks at touch-down, before any travel; then the
            // velocity, if any, says which way. A leftward start is refused.
            var d = pan.translation(in: nav.view)
            if d == .zero { d = pan.velocity(in: nav.view) }
            if d == .zero { return true }
            return d.x > 0 && d.x >= abs(d.y) * SwipeRule.dominance
        }
        return true
    }
}

/// Back from a rightward swipe that starts in the left 32 pt of the reader
/// (REDESIGN §3.0). A pan on the navigation controller's view whose action is
/// UIKit's own interactive-pop handler, the object behind the edge Back pan,
/// so the screen follows the finger and finishes or springs back exactly as
/// the system Back does. Should that handler ever be missing, a committed
/// swipe (`SwipeRule.commits`) pops with the standard animation instead.
private final class BackStripPan: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var nav: UINavigationController?
    private weak var driver: NSObject?
    private static let popAction = NSSelectorFromString("handleNavigationTransition:")

    init() {
        super.init(target: nil, action: nil)
        maximumNumberOfTouches = 1
        delegate = self
    }

    func install(on nav: UINavigationController, driver: AnyObject?) {
        uninstall()
        self.nav = nav
        if let d = driver as? NSObject, d.responds(to: Self.popAction) {
            self.driver = d
            addTarget(d, action: Self.popAction)
        } else {
            addTarget(self, action: #selector(fallback))
        }
        nav.view.addGestureRecognizer(self)
    }

    func uninstall() {
        if let d = driver { removeTarget(d, action: Self.popAction) }
        removeTarget(self, action: #selector(fallback))
        view?.removeGestureRecognizer(self)
        driver = nil
    }

    @objc private func fallback() {
        guard state == .ended, let nav, let width = view?.bounds.width else { return }
        let t = translation(in: view).x
        if SwipeRule.commits(translation: t, velocity: velocity(in: view).x, width: width) {
            nav.popViewController(animated: true)
        }
    }

    // Only touches that start in the strip.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let nav else { return false }
        return touch.location(in: nav.view).x <= SwipeRule.backZone
    }

    // Only rightward, 2:1 horizontal, with somewhere to go back to.
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let nav, nav.viewControllers.count > 1, nav.transitionCoordinator == nil else { return false }
        let d = translation(in: nav.view)
        return d.x > 0 && d.x >= abs(d.y) * SwipeRule.dominance
    }

    // The reader's vertical scroll waits a moment for this to decide, but only
    // for touches in the strip (this one doesn't receive the others).
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && other.view is UIScrollView
    }
}
