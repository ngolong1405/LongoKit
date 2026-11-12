import CoreGraphics
@preconcurrency import Vision

/// Reads the text in a capture with Vision, on this Mac: nothing is sent anywhere. Any script Vision knows: Chinese,
/// Japanese, Korean, Thai, Cyrillic, Arabic and the Latin languages, Vietnamese with its marks.
enum TextRecognizer {
    /// Recognized lines, top to bottom. `vietnameseFirst` puts Vietnamese ahead of English when the text is Latin.
    static func lines(in image: CGImage, vietnameseFirst: Bool) async throws -> [String] {
        // Two readings of the same picture. One detects the language by itself, so it reads Chinese, Korean and the
        // rest, but drops Vietnamese marks on Latin text ("Xin chao"). The other reads Latin text as Vietnamese and
        // English, marks and all, but nothing else. Each line takes the reading that suits it.
        let anyScript = VNRecognizeTextRequest()
        anyScript.recognitionLevel = .accurate
        anyScript.usesLanguageCorrection = true
        anyScript.automaticallyDetectsLanguage = true
        let latin = VNRecognizeTextRequest()
        latin.recognitionLevel = .accurate
        latin.usesLanguageCorrection = true
        latin.recognitionLanguages = latinLanguages(for: latin, vietnameseFirst: vietnameseFirst)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([anyScript, latin])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let latinLines = (latin.results ?? []).compactMap { line in line.topCandidates(1).first.map { (line.boundingBox, $0.string) } }
        return (anyScript.results ?? []).compactMap { line -> String? in
            guard let text = line.topCandidates(1).first?.string else { return nil }
            guard isLatin(text), let twin = latinLines.max(by: { overlap($0.0, line.boundingBox) < overlap($1.0, line.boundingBox) }),
                  overlap(twin.0, line.boundingBox) > 0.5 else { return text }
            return twin.1
        }
    }

    /// Recognized lines read as one language (a code from `languages`), top to bottom.
    static func lines(in image: CGImage, language: String) async throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [language]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// Every language Vision reads on this Mac, as its codes ("vi-VT", "zh-Hans", …).
    static var languages: [String] {
        (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
    }

    /// Vision calls Vietnamese "vi-VT".
    static func latinLanguages(for request: VNRecognizeTextRequest, vietnameseFirst: Bool) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
        let wanted = vietnameseFirst ? ["vi-VT", "en-US"] : ["en-US", "vi-VT"]
        let languages = wanted.filter(supported.contains)
        return languages.isEmpty ? ["en-US"] : languages
    }

    /// Only Latin letters (with Vietnamese's), digits, punctuation and symbols: no other script.
    static func isLatin(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value < 0x0370 || (0x1E00...0x1EFF).contains(value) || (0x2000...0x2BFF).contains(value)
        }
    }

    /// How much two boxes cover each other: shared area over the area of both.
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        guard !shared.isNull else { return 0 }
        let both = a.width * a.height + b.width * b.height - shared.width * shared.height
        return both > 0 ? shared.width * shared.height / both : 0
    }
}
