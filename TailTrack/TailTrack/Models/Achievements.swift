import Foundation

/// A flying milestone. Badges unlock locally from the logbook and, when
/// Game Center is connected, report to the matching achievement there.
struct Achievement: Identifiable {
    let id: String          // Game Center achievement ID
    let title: String
    let detail: String
    let icon: String        // SF Symbol
    let isUnlocked: ([Flight]) -> Bool
}

enum AchievementCatalog {

    static let all: [Achievement] = [
        Achievement(id: "tailtrack.first_flight",
                    title: "First Tracked Flight",
                    detail: "Log your first flight",
                    icon: "airplane.circle.fill",
                    isUnlocked: { $0.count >= 1 }),
        Achievement(id: "tailtrack.ten_flights",
                    title: "Frequent Flyer",
                    detail: "Log 10 flights",
                    icon: "repeat.circle.fill",
                    isUnlocked: { $0.count >= 10 }),
        Achievement(id: "tailtrack.fifty_flights",
                    title: "Seasoned Pilot",
                    detail: "Log 50 flights",
                    icon: "star.circle.fill",
                    isUnlocked: { $0.count >= 50 }),
        Achievement(id: "tailtrack.ten_hours",
                    title: "Ten Hours Aloft",
                    detail: "10 hours of tracked flight time",
                    icon: "clock.fill",
                    isUnlocked: { flights in
                        flights.compactMap(\.flightTime).reduce(0, +) >= 10 * 3600
                    }),
        Achievement(id: "tailtrack.cross_country",
                    title: "Cross-Country",
                    detail: "One flight of 50+ nm",
                    icon: "map.fill",
                    isUnlocked: { flights in
                        flights.contains { $0.distanceFlownNM >= 50 || ($0.routeDistanceNM ?? 0) >= 50 }
                    }),
        Achievement(id: "tailtrack.long_hauler",
                    title: "Long Hauler",
                    detail: "One flight of 250+ nm",
                    icon: "globe.americas.fill",
                    isUnlocked: { flights in
                        flights.contains { $0.distanceFlownNM >= 250 }
                    }),
        Achievement(id: "tailtrack.high_flyer",
                    title: "High Flyer",
                    detail: "Reach 10,000 ft",
                    icon: "mountain.2.fill",
                    isUnlocked: { flights in
                        flights.contains { ($0.maxAltitudeFt ?? 0) >= 10_000 }
                    }),
        Achievement(id: "tailtrack.speedster",
                    title: "Speed Demon",
                    detail: "150+ kt over the ground",
                    icon: "gauge.with.needle.fill",
                    isUnlocked: { flights in
                        flights.contains { ($0.maxGroundSpeedKt ?? 0) >= 150 }
                    }),
        Achievement(id: "tailtrack.explorer",
                    title: "Airport Explorer",
                    detail: "Visit 5 different airports",
                    icon: "signpost.right.fill",
                    isUnlocked: { flights in
                        var idents = Set<String>()
                        for flight in flights {
                            if let dep = flight.departure?.ident { idents.insert(dep) }
                            if let dest = flight.destination?.ident { idents.insert(dest) }
                        }
                        return idents.count >= 5
                    }),
    ]

    static func unlockedIDs(for flights: [Flight]) -> [String] {
        all.filter { $0.isUnlocked(flights) }.map(\.id)
    }
}
