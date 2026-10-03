//
//  RideAddressResolver.swift
//  Spoke
//

import CoreLocation
import Foundation
import MapKit

@MainActor
enum RideAddressResolver {
    private static let minimumPointOfInterestRadius: CLLocationDistance = 100
    private static let maximumPointOfInterestRadius: CLLocationDistance = 150

    static func endpointName(for location: RideLocationSample) async -> String? {
        let endpointLocation = CLLocation(
            latitude: location.latitude,
            longitude: location.longitude
        )

        let searchRadius = min(
            max(
                minimumPointOfInterestRadius,
                max(location.horizontalAccuracy, 0) + 50
            ),
            maximumPointOfInterestRadius
        )

        if let placeName = await nearbyPointOfInterestName(
            for: endpointLocation,
            radius: searchRadius
        ) {
            return placeName
        }

        return await reverseGeocodedName(for: endpointLocation)
    }

    static func nearestPointOfInterestName(
        to location: CLLocation,
        among mapItems: [MKMapItem],
        maximumDistance: CLLocationDistance
    ) -> String? {
        mapItems
            .filter { $0.pointOfInterestCategory != nil }
            .compactMap { mapItem -> (name: String, distance: CLLocationDistance)? in
                guard let name = RideAddressFormatter.placeName(from: mapItem.name)
                else { return nil }

                return (
                    name: name,
                    distance: mapItem.location.distance(from: location)
                )
            }
            .filter { $0.distance <= maximumDistance }
            .min { $0.distance < $1.distance }?
            .name
    }

    private static func nearbyPointOfInterestName(
        for location: CLLocation,
        radius: CLLocationDistance
    ) async -> String? {
        let request = MKLocalPointsOfInterestRequest(
            center: location.coordinate,
            radius: radius
        )
        request.pointOfInterestFilter = .includingAll

        do {
            let response = try await MKLocalSearch(request: request).start()
            return nearestPointOfInterestName(
                to: location,
                among: response.mapItems,
                maximumDistance: radius
            )
        } catch {
            return nil
        }
    }

    private static func reverseGeocodedName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }

        do {
            let mapItems = try await request.mapItems

            if let placeName = mapItems.lazy
                .filter({ $0.pointOfInterestCategory != nil })
                .compactMap({ RideAddressFormatter.placeName(from: $0.name) })
                .first
            {
                return placeName
            }

            for mapItem in mapItems {
                let addressCandidates = [
                    mapItem.addressRepresentations?.fullAddress(
                        includingRegion: false,
                        singleLine: false
                    ),
                    mapItem.address?.shortAddress,
                    mapItem.address?.fullAddress,
                ]

                if let street = addressCandidates.lazy.compactMap({
                    RideAddressFormatter.street(from: $0)
                }).first {
                    return street
                }
            }

            return nil
        } catch {
            return nil
        }
    }
}

enum RideAddressFormatter {
    nonisolated private static let maximumPlaceNameLength = 14

    nonisolated static func placeName(from name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }

        guard name.count > maximumPlaceNameLength else { return name }
        return "\(name.prefix(maximumPlaceNameLength))..."
    }

    nonisolated static func street(from address: String?) -> String? {
        let firstLine = address?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .first

        let street = firstLine?
            .split(separator: ",", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return street.flatMap { $0.isEmpty ? nil : $0 }
    }
}
