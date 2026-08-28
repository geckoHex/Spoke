//
//  RideSoundtrackEntry.swift
//  Spoke
//

import Foundation
import SwiftData

@Model
final class RideSoundtrackEntry {
    var spotifyTrackID: String?
    var albumArtURLString: String?

    @Attribute(.externalStorage)
    var albumArtData: Data?

    var title: String
    var artist: String
    var startedAt: Date
    var ride: TrackedRide?

    init(
        spotifyTrackID: String?,
        albumArtURL: URL?,
        title: String,
        artist: String,
        startedAt: Date,
        ride: TrackedRide? = nil
    ) {
        self.spotifyTrackID = spotifyTrackID
        albumArtURLString = albumArtURL?.absoluteString
        albumArtData = nil
        self.title = title
        self.artist = artist
        self.startedAt = startedAt
        self.ride = ride
    }

    var albumArtURL: URL? {
        albumArtURLString.flatMap(URL.init(string:))
    }

    var trackIdentity: String {
        if let spotifyTrackID, !spotifyTrackID.isEmpty {
            return "spotify:\(spotifyTrackID)"
        }

        return "metadata:\(title)\u{1F}\(artist)"
    }
}
