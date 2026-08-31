//
//  RideHUDMapView.swift
//  Spoke
//

import CoreLocation
import MapKit
import SwiftUI

struct RideHUDMapView: UIViewRepresentable {
    let initialMapState: RideMapState?
    let cameraDistance: CLLocationDistance

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .default
        )
        configuration.pointOfInterestFilter = .excludingAll

        mapView.preferredConfiguration = configuration
        mapView.overrideUserInterfaceStyle = .dark
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false

        position(mapView, using: initialMapState, animated: false)
        mapView.setUserTrackingMode(.followWithHeading, animated: true)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if !context.coordinator.hasPositionedMap, initialMapState != nil {
            position(mapView, using: initialMapState, animated: false)
            context.coordinator.hasPositionedMap = true
        }

        if mapView.userTrackingMode != .followWithHeading {
            mapView.setUserTrackingMode(.followWithHeading, animated: true)
        }
    }

    private func position(
        _ mapView: MKMapView,
        using mapState: RideMapState?,
        animated: Bool
    ) {
        guard let mapState else { return }

        let location = mapState.location
        let camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            ),
            fromDistance: cameraDistance,
            pitch: 0,
            heading: mapState.heading ?? 0
        )
        mapView.setCamera(camera, animated: animated)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var hasPositionedMap = false

        func mapView(
            _ mapView: MKMapView,
            didChange mode: MKUserTrackingMode,
            animated: Bool
        ) {
            guard mode == .followWithHeading else { return }
            hasPositionedMap = true
        }
    }
}
