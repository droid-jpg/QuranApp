import CoreLocation
import CoreMotion
import Combine
import SwiftUI

// Mecca coordinates
private let meccaLat = 21.4225
private let meccaLon = 39.8262

@MainActor
class QiblaService: NSObject, ObservableObject {
    @Published var qiblaHeading: Double = 0      // bearing from North to Qibla (degrees)
    @Published var deviceHeading: Double = 0     // raw magnetic heading of the device
    /// Continuous (unwrapped), low-pass-smoothed heading used to drive the on-screen
    /// compass rose. Unwrapping keeps it monotonic across the 0°/360° seam so rotations
    /// never animate the long way round; smoothing damps magnetometer jitter.
    @Published var displayHeading: Double = 0
    @Published var qiblaAngle: Double = 0        // continuous angle to rotate the needle on screen
    @Published var locationStatus: LocationStatus = .notDetermined
    @Published var hasHeading = false

    enum LocationStatus { case notDetermined, denied, ready }

    private let locationManager = CLLocationManager()
    private var userLat: Double = 0
    private var userLon: Double = 0
    /// Low-pass weight applied to each new heading sample (0 = frozen, 1 = no smoothing).
    private let headingSmoothing = 0.15
    private var headingInitialized = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        // Report every sample so the low-pass filter has enough data to converge
        // smoothly rather than snapping between coarse 1° steps.
        locationManager.headingFilter = kCLHeadingFilterNone
    }

    func start() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        default:
            locationStatus = .denied
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    // Great-circle bearing from user → Mecca
    private func computeQiblaHeading(lat: Double, lon: Double) -> Double {
        let φ1 = lat  * .pi / 180
        let φ2 = meccaLat * .pi / 180
        let Δλ = (meccaLon - lon) * .pi / 180

        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x) * 180 / .pi
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension QiblaService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.userLat = loc.coordinate.latitude
            self.userLon = loc.coordinate.longitude
            self.qiblaHeading = self.computeQiblaHeading(lat: self.userLat, lon: self.userLon)
            self.locationStatus = .ready
            self.updateAngle()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.deviceHeading = newHeading.magneticHeading
            if !self.headingInitialized {
                self.displayHeading = newHeading.magneticHeading
                self.headingInitialized = true
            } else {
                // Low-pass the unwrapped delta: damps magnetometer jitter while keeping
                // the value continuous across the 0°/360° seam.
                self.displayHeading += self.normalizeDelta(newHeading.magneticHeading - self.displayHeading) * self.headingSmoothing
            }
            self.hasHeading = true
            self.updateAngle()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            case .denied, .restricted:
                self.locationStatus = .denied
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /// Wraps a degree delta into [-180, 180] so any rotation takes the short path
    /// rather than spinning the long way round the 0°/360° seam.
    func normalizeDelta(_ d: Double) -> Double {
        var x = d.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 } else if x < -180 { x += 360 }
        return x
    }

    private func updateAngle() {
        // Drive the needle off the smoothed heading and accumulate continuously so the
        // rotation never wraps the long way round when the heading crosses north.
        let target = qiblaHeading - displayHeading
        qiblaAngle += normalizeDelta(target - qiblaAngle)
    }
}
