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
            guard let address = mapItems.first?.address else { return nil }
            return normalized(address.shortAddress) ?? normalized(address.fullAddress)
        } catch {
            return nil
        }
    }

    private static func normalized(_ address: String?) -> String? {
        let singleLineAddress = address?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        return singleLineAddress.flatMap { $0.isEmpty ? nil : $0 }
    }
}
