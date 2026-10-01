import Foundation
import OSLog

// Semantic events only. Wording and scheduling live here, never in the ride tracker.
enum LiveRideEvent: Equatable, Sendable {
    case speedChanged(Int)
    case streetChanged(String)
    case enteredCity(String)
    case distanceMilestone(Int)
    case clockTime(Date)
    case rideDuration(TimeInterval)

    enum Category: Int, CaseIterable, Sendable {
        case speed = 20, clockTime = 40, rideDuration = 50
        case distance = 70, streets = 80, cities = 100
    }

    var category: Category {
        switch self {
        case .speedChanged: .speed
        case .streetChanged: .streets
        case .enteredCity: .cities
        case .distanceMilestone: .distance
        case .clockTime: .clockTime
        case .rideDuration: .rideDuration
        }
    }

    var lifetime: TimeInterval {
        switch self {
        case .speedChanged: 3
        case .enteredCity: 12
        default: 8
        }
    }

    var text: String {
        switch self {
        case .speedChanged(let speed):
            return "Speed \(speed)."
        case .streetChanged(let street):
            return "Turned onto \(street)."
        case .enteredCity(let city):
            return "Entered \(city)."
        case .distanceMilestone(let miles):
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .spellOut
            let number = formatter.string(from: NSNumber(value: miles)) ?? "\(miles)"
            return "\(number.prefix(1).uppercased())\(number.dropFirst()) \(miles == 1 ? "mile" : "miles")."
        case .clockTime(let date):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "h:mm a"
            return "Time \(formatter.string(from: date))."
        case .rideDuration(let duration):
            let minutes = max(Int(duration / 60), 0)
            let hours = minutes / 60
            let remainder = minutes % 60
            guard hours > 0 else { return "Riding for \(minutes) minutes." }
            let hourText = hours == 1 ? "one hour" : "\(hours) hours"
            let minuteText = remainder == 0 ? "" : " and \(remainder) \(remainder == 1 ? "minute" : "minutes")"
            return "Riding for \(hourText)\(minuteText)."
        }
    }
}

struct LiveRideConfiguration: Equatable {
    var enabled = false
    var voiceIdentifier = ""
    var categories = Set(LiveRideEvent.Category.allCases)

    init() {}

    init(settings: AppSettings?) {
        guard let settings else { return }
        enabled = settings.liveRideEnabled
        voiceIdentifier = settings.liveRideVoiceIdentifier
        categories = []
        if settings.liveRideSpeedEnabled { categories.insert(.speed) }
        if settings.liveRideStreetsEnabled { categories.insert(.streets) }
        if settings.liveRideCitiesEnabled { categories.insert(.cities) }
        if settings.liveRideDistanceEnabled { categories.insert(.distance) }
        if settings.liveRideClockTimeEnabled { categories.insert(.clockTime) }
        if settings.liveRideDurationEnabled { categories.insert(.rideDuration) }
    }
}

struct LiveRidePolicy {
    struct Pending {
        let event: LiveRideEvent
        let observedAt: Date

        func isFresh(at date: Date) -> Bool {
            (0...event.lifetime).contains(date.timeIntervalSince(observedAt))
        }
    }

    static let logger = Logger(subsystem: "Spoke", category: "LiveRide")
    private(set) var pending: Pending?
    private var latestSpeed: Pending?
    private var lastSpeed: Int?
    private var lastSpeedAt: Date?
    private var lastNarrationAt: Date?
    private var lastSpoken: [LiveRideEvent.Category: LiveRideEvent] = [:]
    var categories = Set(LiveRideEvent.Category.allCases)

    mutating func submit(_ event: LiveRideEvent, at date: Date) {
        discardExpired(at: date)
        guard categories.contains(event.category) else {
            log(event, "SUPPRESSED: CATEGORY DISABLED")
            return
        }

        if case .speedChanged(let speed) = event {
            guard (0...120).contains(speed) else { return }
            latestSpeed = Pending(event: event, observedAt: date)
            // Even a suppressed new reading invalidates an older pending speed.
            if pending?.event.category == .speed { pending = nil }
            guard speedIsEligible(speed, at: date) else {
                log(event, "SUPPRESSED: DELTA TOO SMALL OR COOLDOWN")
                return
            }
        } else if lastSpoken[event.category] == event {
            log(event, "SUPPRESSED: ALREADY SPOKEN")
            return
        }

        offer(Pending(event: event, observedAt: date))
    }

    mutating func refresh(at date: Date) {
        discardExpired(at: date)
        if let latestSpeed, latestSpeed.isFresh(at: date),
           categories.contains(.speed),
           case .speedChanged(let speed) = latestSpeed.event,
           speedIsEligible(speed, at: date), pending == nil {
            offer(latestSpeed)
        }
    }

    mutating func takeNext(at date: Date) -> LiveRideEvent? {
        refresh(at: date)
        guard let next = pending else { return nil }
        pending = nil
        return next.event
    }

    mutating func didStart(_ event: LiveRideEvent, at date: Date) {
        lastSpoken[event.category] = event
        lastNarrationAt = date
        if case .speedChanged(let speed) = event {
            lastSpeed = speed
            lastSpeedAt = date
        }
        log(event, "SPOKEN")
    }

    mutating func didFinish(at date: Date) {
        lastNarrationAt = date
    }

    mutating func invalidate(_ category: LiveRideEvent.Category) {
        if let pending, pending.event.category == category {
            log(pending.event, "DISCARDED: NO LONGER RELEVANT")
            self.pending = nil
        }
        if category == .speed { latestSpeed = nil }
    }

    private func speedIsEligible(_ speed: Int, at date: Date) -> Bool {
        guard let lastSpeed, let lastSpeedAt else { return true }
        let delta = abs(speed - lastSpeed)
        let elapsed = date.timeIntervalSince(lastSpeedAt)
        if delta >= 3 && elapsed >= 2 { return true }
        if delta >= 2 && elapsed >= 4 { return true }
        return date.timeIntervalSince(lastNarrationAt ?? lastSpeedAt) >= 18
    }

    private mutating func offer(_ candidate: Pending) {
        if let pending {
            guard candidate.event.category.rawValue >= pending.event.category.rawValue else {
                log(candidate.event, "SUPPRESSED: HIGHER PRIORITY PENDING")
                return
            }
            // Re-observing the same contextual event must not extend its expiry.
            if candidate.event == pending.event && candidate.event.category != .speed { return }
            log(candidate.event, "REPLACED \(pending.event.category)")
        } else {
            log(candidate.event, "PENDING")
        }
        pending = candidate
    }

    private mutating func discardExpired(at date: Date) {
        guard let pending else { return }
        if !pending.isFresh(at: date) || !categories.contains(pending.event.category) {
            log(pending.event, "EXPIRED OR DISABLED")
            self.pending = nil
        }
    }

    private func log(_ event: LiveRideEvent, _ decision: String) {
        #if DEBUG
        Self.logger.debug("\(event.text, privacy: .public) → \(decision, privacy: .public)")
        #else
        Self.logger.debug("\(event.text, privacy: .private) → \(decision, privacy: .public)")
        #endif
    }
}

// Baselines prevent catch-up narration after a pause, a relaunch, or enabling the feature.
struct LiveRideProgress {
    private var mile: Int
    private var durationInterval: Int
    private var clockInterval: Int

    init(distance: Double, duration: TimeInterval, now: Date) {
        mile = Int(max(distance, 0) / 1_609.344)
        durationInterval = Int(max(duration, 0) / 300)
        clockInterval = Self.clockInterval(at: now)
    }

    mutating func events(distance: Double, duration: TimeInterval, now: Date) -> [LiveRideEvent] {
        let next = LiveRideProgress(distance: distance, duration: duration, now: now)
        defer { self = next }
        var events: [LiveRideEvent] = []
        if next.mile > mile { events.append(.distanceMilestone(next.mile)) }
        // A suspended process must not describe an old duration or clock boundary as current.
        if next.durationInterval > durationInterval, duration.truncatingRemainder(dividingBy: 300) < 8 {
            events.append(.rideDuration(Double(next.durationInterval * 300)))
        }
        if next.clockInterval != clockInterval,
           Calendar.autoupdatingCurrent.component(.minute, from: now) % 3 == 0,
           Calendar.autoupdatingCurrent.component(.second, from: now) < 8 {
            events.append(.clockTime(now))
        }
        return events
    }

    private static func clockInterval(at date: Date) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 60) +
            (calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)) / 3 * 3
    }
}

struct LiveRidePlaceConfirmation {
    private(set) var confirmed: String?
    private var candidate: String?
    private var observations = 0
    private var candidateSince: Date?
    private var changedAt: Date?

    mutating func observe(_ name: String?, at date: Date, isCity: Bool) -> String? {
        guard let name, !name.isEmpty else {
            candidate = nil
            observations = 0
            return nil
        }
        if name.localizedCaseInsensitiveCompare(confirmed ?? "") == .orderedSame {
            candidate = nil
            observations = 0
            return nil
        }
        if name.localizedCaseInsensitiveCompare(candidate ?? "") != .orderedSame {
            candidate = name
            candidateSince = date
            observations = 0
        }
        observations += 1
        guard observations >= (isCity ? 3 : 2),
              date.timeIntervalSince(candidateSince ?? date) >= (isCity ? 10 : 5),
              changedAt.map({ date.timeIntervalSince($0) >= (isCity ? 60 : 20) }) ?? true
        else { return nil }
        let hadBaseline = confirmed != nil
        confirmed = name
        changedAt = hadBaseline ? date : nil
        candidate = nil
        observations = 0
        return hadBaseline ? name : nil
    }
}
