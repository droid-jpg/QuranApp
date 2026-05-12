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
    @Published var deviceHeading: Double = 0     // magnetic heading of the device
    @Published var qiblaAngle: Double = 0        // angle to rotate the needle on screen
    @Published var locationStatus: LocationStatus = .notDetermined
    @Published var hasHeading = false

    enum LocationStatus { case notDetermined, denied, ready }

    private let locationManager = CLLocationManager()
    private var userLat: Double = 0
    private var userLon: Double = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.headingFilter = 1
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

    private func updateAngle() {
        // Rotate the needle so it points toward Qibla
        qiblaAngle = qiblaHeading - deviceHeading
    }
}
