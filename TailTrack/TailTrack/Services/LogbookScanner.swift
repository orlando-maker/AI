import UIKit
import Vision

/// On-device OCR for paper logbook pages, using Apple's Vision framework —
/// no cloud service or API key involved. Observations are regrouped into
/// table rows by their vertical position so a logbook line stays one line.
enum LogbookScanner {

    struct RecognizedFragment {
        let text: String
        let midY: CGFloat
        let minX: CGFloat
    }

    static func recognizeRows(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let fragments: [RecognizedFragment] = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            let observations = request.results ?? []
            return observations.compactMap { obs in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return RecognizedFragment(text: candidate.string,
                                          midY: obs.boundingBox.midY,
                                          minX: obs.boundingBox.minX)
            }
        }.value

        // Vision's normalized coordinates put y=0 at the bottom; group
        // fragments whose vertical centers are close into one row, then
        // order each row left→right.
        let sorted = fragments.sorted { $0.midY > $1.midY }
        var rows: [[RecognizedFragment]] = []
        for fragment in sorted {
            if var last = rows.last, let anchor = last.first,
               abs(anchor.midY - fragment.midY) < 0.012 {
                last.append(fragment)
                rows[rows.count - 1] = last
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: "  ")
        }
    }
}
