import SwiftUI
import CoreLocation

struct QiblaView: View {
    @StateObject private var qibla = QiblaService()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 40) {
                // Status / distance card
                statusCard

                // Compass
                compassDial

                // Degree label
                if qibla.locationStatus == .ready {
                    VStack(spacing: 4) {
                        Text("\(Int(qibla.qiblaHeading))°")
                            .font(.system(size: 48, weight: .thin, design: .rounded))
                        Text("from North")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.top, 32)
        }
        .navigationTitle("Qibla")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear  { qibla.start() }
        .onDisappear { qibla.stop() }
    }

    // MARK: - Status card

    @ViewBuilder
    private var statusCard: some View {
        switch qibla.locationStatus {
        case .notDetermined:
            InfoBanner(
                icon: "location.circle",
                color: .brand,
                message: "Allow location access to find your Qibla direction."
            )
        case .denied:
            InfoBanner(
                icon: "location.slash",
                color: .red,
                message: "Location access denied. Enable it in Settings → Privacy → Location."
            )
        case .ready:
            InfoBanner(
                icon: "location.fill",
                color: .green,
                message: qibla.hasHeading
                    ? "Point your phone upward and rotate slowly."
                    : "Getting compass reading…"
            )
        }
    }

    // MARK: - Compass dial

    private var compassDial: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.brand.opacity(0.6), Color.brand.opacity(0.15)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 4
                )
                .frame(width: 280, height: 280)

            // Rotating rose: ticks + cardinal letters turn together so North always
            // tracks true north. The whole rose spins by -displayHeading; letters
            // counter-rotate by the same amount so their glyphs stay upright.
            ZStack {
                // Tick marks
                ForEach(0..<36) { i in
                    Rectangle()
                        .fill(Color(.secondaryLabel).opacity(0.4))
                        .frame(width: 1, height: i % 9 == 0 ? 12 : 6)
                        .offset(y: -125)
                        .rotationEffect(.degrees(Double(i) * 10))
                }

                // Cardinal direction labels — kept upright via counter-rotation
                ForEach([("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)], id: \.0) { label, angle in
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(label == "N" ? Color.red : Color(.secondaryLabel))
                        .rotationEffect(.degrees(qibla.displayHeading - angle))
                        .offset(y: -120)
                        .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.degrees(-qibla.displayHeading))
            .animation(.interpolatingSpring(stiffness: 70, damping: 14), value: qibla.displayHeading)

            // Qibla needle
            QiblaNeedle()
                .rotationEffect(.degrees(qibla.qiblaAngle))
                .animation(.interpolatingSpring(stiffness: 70, damping: 14), value: qibla.qiblaAngle)
                .opacity(qibla.locationStatus == .ready ? 1 : 0.25)

            // Centre dot
            Circle()
                .fill(Color.brand)
                .frame(width: 12, height: 12)
        }
        .frame(width: 280, height: 280)
    }
}

// MARK: - Needle shape

struct QiblaNeedle: View {
    var body: some View {
        ZStack {
            // Gold tip pointing toward Qibla
            Triangle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.65, blue: 0.1), Color(red: 0.6, green: 0.45, blue: 0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 18, height: 90)
                .offset(y: -45)

            // Grey tail
            Triangle()
                .fill(Color(.systemGray3))
                .frame(width: 14, height: 70)
                .rotationEffect(.degrees(180))
                .offset(y: 35)
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
