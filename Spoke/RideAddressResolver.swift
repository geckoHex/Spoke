//
//  RideAddressResolver.swift
//  Spoke
//

import CoreLocation
import Foundation
import MapKit

@MainActor
enum RideAddressResolver {
    static func endpointName(for location: RideLocationSample) async -> String? {
        let location = CLLocation(
            latitude: location.latitude,
            longitude: location.longitude
        )
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
