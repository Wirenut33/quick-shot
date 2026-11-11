//
//  TextRecognizer.swift
//  QuickShot
//

import CoreGraphics
import Foundation
import Vision

/// Reads text and QR codes from an image. Everything runs on this Mac; nothing is sent anywhere.
enum TextRecognizer {
    /// Recognised lines in reading order, followed by any QR code contents that are
    /// not already part of the text. Empty when the image holds neither.
    nonisolated static func recognize(_ image: CGImage) throws -> String {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true

        let codes = VNDetectBarcodesRequest()
        codes.symbologies = [.qr]

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([text, codes])

        let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        var parts = lines
        for payload in (codes.results ?? []).compactMap(\.payloadStringValue) where !parts.contains(payload) {
            parts.append(payload)
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs recognition away from the main thread.
    static func recognizeInBackground(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try TextRecognizer.recognize(image)
        }.value
    }
}
