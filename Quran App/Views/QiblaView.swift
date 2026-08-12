import SwiftUI
import CoreLocation

/// The compass. A dial is the one thing on this screen that has to be round, so
/// it stays — but the ring is a hairline, the needle drops its gold gradient for
/// the accent (which now follows the chosen theme), and the bearing is set in
/// the reading serif like every other number in the app.
struct QiblaView: View {
    @StateObject private var qibla = QiblaService()

    var body: some View {
        VStack(spacing: 34) {
            statusLine
                .padding(.horizontal, 24)

            compassDial

            if qibla.locationStatus == .ready {
                VStack(spacing: 6) {
                    Text("\(Int(qibla.qiblaHeading))°")
                        .font(.appSerif(52, weight: .light))
                        .contentTransition(.numericText())
                    Eyebrow("From north")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .navigationTitle("Qibla")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { qibla.start() }
        .onDisappear { qibla.stop() }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLine: some View {
        switch qibla.locationStatus {
        case .notDetermined:
            InfoBanner(icon: "location.circle", color: .brand,
                       message: "Allow location access to find your Qibla direction.")
        case .denied:
            InfoBanner(icon: "location.slash", color: .red,
                       message: "Location access denied. Enable it in Settings → Privacy → Location.")
        case .ready:
            InfoBanner(icon: "location.fill", color: .brand,
                       message: qibla.hasHeading
                           ? "Point your phone upward and rotate slowly."
                           : "Getting compass reading…")
        }
    }

    // MARK: - Compass dial

    private var compassDial: some View {
        ZStack {
            Circle()
                .strokeBorder(Color(.label).opacity(0.14), lineWidth: 1)
                .frame(width: 280, height: 280)

            // Rotating rose: ticks + cardinal letters turn together so North always
            // tracks true north. The whole rose spins by -displayHeading; letters
            // counter-rotate by the same amount so their glyphs stay upright.
            ZStack {
                ForEach(0..<36) { i in
                    Rectangle()
                        .fill(Color(.label).opacity(i % 9 == 0 ? 0.4 : 0.18))
                        .frame(width: 1, height: i % 9 == 0 ? 12 : 6)
                        .offset(y: -125)
                        .rotationEffect(.degrees(Double(i) * 10))
                }

                ForEach([("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)], id: \.0) { label, angle in
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(label == "N" ? Color.brand : Color(.label).opacity(0.4))
                        .rotationEffect(.degrees(qibla.displayHeading - angle))
                        .offset(y: -105)
                        .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.degrees(-qibla.displayHeading))
            .animation(.interpolatingSpring(stiffness: 70, damping: 14), value: qibla.displayHeading)

            QiblaNeedle()
                .rotationEffect(.degrees(qibla.qiblaAngle))
                .animation(.interpolatingSpring(stiffness: 70, damping: 14), value: qibla.qiblaAngle)
                .opacity(qibla.locationStatus == .ready ? 1 : 0.25)

            Circle()
                .fill(Color.brand)
                .frame(width: 7, height: 7)
        }
        .frame(width: 280, height: 280)
    }
}

// MARK: - Needle

struct QiblaNeedle: View {
    var body: some View {
        ZStack {
            // Accent tip toward the Qibla…
            Triangle()
                .fill(Color.brand)
                .frame(width: 14, height: 88)
                .offset(y: -44)

            // …and a hollow tail, so the direction reads at a glance.
            Triangle()
                .stroke(Color(.label).opacity(0.25), lineWidth: 1)
                .frame(width: 12, height: 68)
                .rotationEffect(.degrees(180))
                .offset(y: 34)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Reusable banner

struct InfoBanner: View {
    let icon: String
    let color: Color
    let message: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(message)
                .font(.appSerif(15))
                .foregroundStyle(Color(.label).opacity(0.6))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .overlay(Rectangle().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}
