import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct ExtractedThumb: Equatable, Sendable {
    public let timestamp: Double
    public let jpegData: Data

    public init(timestamp: Double, jpegData: Data) {
        self.timestamp = timestamp
        self.jpegData = jpegData
    }

    public var base64: String { jpegData.base64EncodedString() }
}

/// F4: extracción de thumbnails JPEG para Gemini vision.
/// Solo AVFoundation — CERO Vision, así que es imposible que mate al
/// MediaAnalysisDaemon (adiós error MAD/XPC). Lo pesado (clasificar) pasa al backend.
public final class FrameExtractorService {
    public static let shared = FrameExtractorService()

    /// Lado mayor del thumb. 320px ≈ 258 tokens/imagen en Gemini.
    public var maxDimension: CGFloat = 320
    public var jpegQuality: CGFloat = 0.6
    /// Espejo del límite del backend (MAX_FRAMES_PER_REQUEST).
    public var maxThumbs: Int = 24

    public init() {}

    /// Extrae JPEGs en los timestamps dados (segundos). Devuelve solo los que salieron bien, ordenados.
    public func extractThumbs(in asset: AVAsset, at timestamps: [Double]) async -> [ExtractedThumb] {
        let times = Array(timestamps.filter { $0 >= 0 }.sorted().prefix(maxThumbs))
        guard !times.isEmpty else { return [] }
        guard (try? await asset.loadTracks(withMediaType: .video).first) != nil else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var out: [ExtractedThumb] = []
        for t in times {
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            guard let imageRef = try? await generator.image(at: cmTime).image else { continue }
            guard let data = Self.jpegData(from: imageRef, quality: jpegQuality) else { continue }
            out.append(ExtractedThumb(timestamp: t, jpegData: data))
        }
        return out
    }

    /// Timestamps sugeridos para un beat: 25% y 75% (pilla movimiento sin gastar de más).
    public static func thumbTimes(forBeat start: Double, end: Double) -> [Double] {
        guard end > start else { return [] }
        let dur = end - start
        if dur < 2.0 { return [(start + end) / 2.0] }
        return [start + dur * 0.25, start + dur * 0.75]
    }

    static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
