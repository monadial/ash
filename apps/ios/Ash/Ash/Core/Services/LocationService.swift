//
//  LocationService.swift
//  Ash
//

import CoreLocation
import Foundation

enum LocationError: Error, Sendable {
    case permissionDenied
    case permissionRestricted
    case locationUnavailable
    case timeout
}

protocol LocationServiceProtocol: Sendable {
    func getCurrentLocation() async throws -> (latitude: Double, longitude: Double)
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestPermissionIfNeeded() async -> Bool
}

final class LocationService: NSObject, LocationServiceProtocol, @unchecked Sendable {
    private let locationManager: CLLocationManager
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var permissionContinuation: CheckedContinuation<Bool, Never>?

    override init() {
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    func requestPermissionIfNeeded() async -> Bool {
        let status = authorizationStatus

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.permissionContinuation = continuation
                DispatchQueue.main.async {
                    self.locationManager.requestWhenInUseAuthorization()
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func getCurrentLocation() async throws -> (latitude: Double, longitude: Double) {
        guard await requestPermissionIfNeeded() else {
            throw LocationError.permissionDenied
        }

        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = continuation

            DispatchQueue.main.async {
                self.locationManager.requestLocation()
            }

            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if self.locationContinuation != nil {
                    self.locationContinuation?.resume(throwing: LocationError.timeout)
                    self.locationContinuation = nil
                }
            }
        }

        let latitude = (location.coordinate.latitude * 1_000_000).rounded() / 1_000_000
        let longitude = (location.coordinate.longitude * 1_000_000).rounded() / 1_000_000

        Log.info(.app, "Location obtained: \(latitude), \(longitude)")

        return (latitude: latitude, longitude: longitude)
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.error(.app, "Location error: \(error.localizedDescription)")

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationContinuation?.resume(throwing: LocationError.permissionDenied)
            default:
                locationContinuation?.resume(throwing: LocationError.locationUnavailable)
            }
        } else {
            locationContinuation?.resume(throwing: LocationError.locationUnavailable)
        }
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            permissionContinuation?.resume(returning: true)
        case .denied, .restricted:
            permissionContinuation?.resume(returning: false)
        case .notDetermined:
            break
        @unknown default:
            permissionContinuation?.resume(returning: false)
        }
        permissionContinuation = nil
    }
}
