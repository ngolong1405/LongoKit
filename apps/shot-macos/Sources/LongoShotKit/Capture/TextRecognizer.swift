import CoreGraphics
@preconcurrency import Vision

/// Reads the text in a capture with Vision, on this Mac: nothing is sent anywhere.
enum TextRecognizer {
    /// Recognized lines, top to bottom. `vietnameseFirst` puts Vietnamese ahead of English when both are supported.
    static func lines(in image: CGImage, vietnameseFirst: Bool) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { return continuation.resume(throwing: error) }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages(for: request, vietnameseFirst: vietnameseFirst)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Vision calls Vietnamese "vi-VT".
    static func languages(for request: VNRecognizeTextRequest, vietnameseFirst: Bool) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
        let wanted = vietnameseFirst ? ["vi-VT", "en-US"] : ["en-US", "vi-VT"]
        let languages = wanted.filter(supported.contains)
        return languages.isEmpty ? ["en-US"] : languages
    }
}
