import SwiftUI

/// Default artwork for aircraft without an uploaded photo: an original,
/// license-free top-down silhouette drawn in code, matched to the type.
enum AircraftCategory {
    case highWingSingle   // C152, C172, Cubs, Citabria…
    case lowWingSingle    // Pipers, Cirrus, Mooney, Bonanza, RVs…
    case twin             // Baron, DA62, Seneca…
    case turboprop        // PC-12, TBM…
    case jet              // Vision Jet, light jets

    static func category(for typeCode: String) -> AircraftCategory {
        let t = typeCode.trimmingCharacters(in: .whitespaces).uppercased()
        if t.isEmpty { return .highWingSingle }

        let highWing = ["J3", "PA18", "CH7A", "CH7B", "BL8", "HUSK", "C77R", "C177"]
        let twins = ["BE58", "BE55", "BE76", "DA62", "PA34", "PA44", "C310", "C337", "P68"]
        let turboprops = ["PC12", "TBM7", "TBM8", "TBM9", "EPIC", "KODI", "C208"]
        let jets = ["SF50", "C510", "C525", "E50P", "E55P", "HDJT"]

        if jets.contains(t) || t.hasPrefix("CJ") { return .jet }
        if turboprops.contains(t) || t.hasPrefix("TBM") { return .turboprop }
        if twins.contains(t) { return .twin }
        if highWing.contains(t) || t.hasPrefix("C1") || t.hasPrefix("C2") { return .highWingSingle }
        return .lowWingSingle
    }
}

/// Top-down aircraft silhouette, nose up, drawn in a normalized 100×100
/// space and scaled to the shape's rect.
struct AircraftTopView: Shape {
    let category: AircraftCategory

    func path(in rect: CGRect) -> Path {
        var p = Path()

        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x / 100 * rect.width,
                   y: rect.minY + y / 100 * rect.height,
                   width: w / 100 * rect.width,
                   height: h / 100 * rect.height)
        }
        func corner(_ r: CGFloat) -> CGSize {
            CGSize(width: r / 100 * rect.width, height: r / 100 * rect.height)
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * rect.width,
                    y: rect.minY + y / 100 * rect.height)
        }
        func polygon(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            p.move(to: pt(first.0, first.1))
            for point in points.dropFirst() { p.addLine(to: pt(point.0, point.1)) }
            p.closeSubpath()
        }

        switch category {
        case .highWingSingle:
            p.addRoundedRect(in: box(38, 8, 24, 3), cornerSize: corner(1.5))    // prop
            p.addEllipse(in: box(46.5, 5, 7, 9))                                 // spinner
            p.addRoundedRect(in: box(45, 9, 10, 74), cornerSize: corner(5))      // fuselage
            p.addRoundedRect(in: box(3, 30, 94, 13), cornerSize: corner(6.5))    // wing
            p.addRoundedRect(in: box(29, 80, 42, 9), cornerSize: corner(4.5))    // tailplane

        case .lowWingSingle:
            p.addRoundedRect(in: box(38, 8, 24, 3), cornerSize: corner(1.5))
            p.addEllipse(in: box(46.5, 5, 7, 9))
            p.addRoundedRect(in: box(45, 9, 10, 74), cornerSize: corner(5))
            // Slightly tapered low wing
            polygon([(46, 36), (5, 44), (3, 52), (5, 55), (46, 52),
                     (54, 52), (95, 55), (97, 52), (95, 44), (54, 36)])
            p.addRoundedRect(in: box(29, 80, 42, 9), cornerSize: corner(4.5))

        case .twin:
            p.addRoundedRect(in: box(45, 12, 10, 72), cornerSize: corner(5))     // fuselage
            p.addEllipse(in: box(46.5, 8, 7, 9))                                 // nose
            p.addRoundedRect(in: box(2, 36, 96, 13), cornerSize: corner(6.5))    // wing
            p.addRoundedRect(in: box(22, 22, 11, 32), cornerSize: corner(5))     // left nacelle
            p.addRoundedRect(in: box(67, 22, 11, 32), cornerSize: corner(5))     // right nacelle
            p.addRoundedRect(in: box(17, 24, 21, 3), cornerSize: corner(1.5))    // left prop
            p.addRoundedRect(in: box(62, 24, 21, 3), cornerSize: corner(1.5))    // right prop
            p.addRoundedRect(in: box(28, 82, 44, 9), cornerSize: corner(4.5))

        case .turboprop:
            p.addRoundedRect(in: box(35, 6, 30, 3.5), cornerSize: corner(1.7))   // big prop
            p.addEllipse(in: box(46, 2, 8, 10))                                  // spinner
            p.addRoundedRect(in: box(44.5, 7, 11, 78), cornerSize: corner(5.5))  // long fuselage
            polygon([(45, 34), (4, 44), (2, 52), (4, 55), (45, 51),
                     (55, 51), (96, 55), (98, 52), (96, 44), (55, 34)])
            p.addRoundedRect(in: box(27, 82, 46, 9), cornerSize: corner(4.5))

        case .jet:
            p.addEllipse(in: box(45, 4, 10, 14))                                 // nose cone
            p.addRoundedRect(in: box(44, 8, 12, 72), cornerSize: corner(6))      // fuselage
            // Swept wings
            polygon([(46, 38), (6, 60), (4, 67), (10, 68), (47, 54),
                     (53, 54), (90, 68), (96, 67), (94, 60), (54, 38)])
            // Swept tail surfaces
            polygon([(48, 74), (28, 88), (30, 92), (49, 84),
                     (51, 84), (70, 92), (72, 88), (52, 74)])
        }
        return p
    }
}

/// Gradient card with the type-matched silhouette — the stand-in wherever
/// an aircraft has no uploaded photo.
struct AircraftArtView: View {
    let typeCode: String
    var inset: CGFloat = 10

    var body: some View {
        ZStack {
            Theme.sky
            AircraftTopView(category: .category(for: typeCode))
                .fill(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                .aspectRatio(1, contentMode: .fit)
                .padding(inset)
        }
    }
}
