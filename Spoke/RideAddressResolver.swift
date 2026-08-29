//
//  RideAddressResolver.swift
//  Spoke
//

import CoreLocation
import Foundation
import MapKit

@MainActor
enum RideAddressResolver {
    static func streetAddress(for location: RideLocationSample) async -> String? {
        let location = CLLocation(
            latitude: location.latitude,
            longitude: location.longitude
        )
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }

        do {
            let mapItems = try await request.mapItems
            guard let mapItem = mapItems.first else { return nil }

            let addressCandidates = [
                mapItem.addressRepresentations?.fullAddress(
                    includingRegion: false,
                    singleLine: false
                ),
                mapItem.address?.shortAddress,
                mapItem.address?.fullAddress,
            ]

            return addressCandidates.lazy.compactMap {
                RideAddressFormatter.street(from: $0)
            }.first
        } catch {
            return nil
        }
    }
}

enum RideAddressFormatter {
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
