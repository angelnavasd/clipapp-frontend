import Foundation
import AVFoundation
import QuartzCore
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Generador de capas de subtítulos dinámicos para quemar en el video con CoreAnimation
public final class SubtitleOverlayGenerator {
    public static let shared = SubtitleOverlayGenerator()

    public init() {}

    /// Genera la jerarquía de CALayers sincronizada para AVVideoCompositionCoreAnimationTool
    public func createSubtitleLayer(
        words: [WordTimestamp],
        highlightWords: [HighlightWord],
        style: SubtitleStyle,
        renderSize: CGSize = CGSize(width: 1080, height: 1920),
        verticalPositionRatio: CGFloat = 0.65 // 0.0 arriba, 1.0 abajo
    ) -> CALayer {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.masksToBounds = true

        guard !words.isEmpty else { return parentLayer }

        // Agrupar palabras en oraciones/chunks de 3 a 5 palabras para legibilidad móvil
        let chunks = groupWordsIntoPhrases(words, maxWordsPerPhrase: 4)

        for chunk in chunks {
            guard let phraseStart = chunk.first?.start, let phraseEnd = chunk.last?.end else { continue }
            let phraseDuration = phraseEnd - phraseStart
            guard phraseDuration > 0 else { continue }

            let phraseLayer = CALayer()
            let phraseHeight: CGFloat = 180
            let phraseWidth: CGFloat = renderSize.width * 0.88
            let phraseY = renderSize.height * verticalPositionRatio

            phraseLayer.frame = CGRect(
                x: (renderSize.width - phraseWidth) / 2.0,
                y: phraseY,
                width: phraseWidth,
                height: phraseHeight
            )
            phraseLayer.opacity = 0.0 // Oculto por defecto

            // Animación de visibilidad de la frase
            let showAnim = CAKeyframeAnimation(keyPath: "opacity")
            showAnim.beginTime = AVCoreAnimationBeginTimeAtZero + phraseStart
            showAnim.duration = phraseDuration
            showAnim.keyTimes = [0.0, 0.05, 0.95, 1.0]
            showAnim.values = [0.0, 1.0, 1.0, 0.0]
            showAnim.isRemovedOnCompletion = false
            showAnim.fillMode = .forwards
            phraseLayer.add(showAnim, forKey: "phraseVisibility")

            // Aplicar estilos específicos
            switch style {
            case .hormozi:
                buildHormoziStyle(
                    in: phraseLayer,
                    chunk: chunk,
                    highlightWords: highlightWords,
                    phraseStart: phraseStart,
                    renderSize: renderSize
                )
            case .minimalDark:
                buildMinimalDarkStyle(
                    in: phraseLayer,
                    chunk: chunk,
                    phraseStart: phraseStart,
                    renderSize: renderSize
                )
            case .karaoke:
                buildKaraokeStyle(
                    in: phraseLayer,
                    chunk: chunk,
                    phraseStart: phraseStart,
                    renderSize: renderSize
                )
            }

            parentLayer.addSublayer(phraseLayer)
        }

        return parentLayer
    }

    private func buildHormoziStyle(
        in layer: CALayer,
        chunk: [WordTimestamp],
        highlightWords: [HighlightWord],
        phraseStart: Double,
        renderSize: CGSize
    ) {
        let fullText = chunk.map { $0.word.uppercased() }.joined(separator: " ")
        let textLayer = CATextLayer()
        textLayer.string = fullText
        textLayer.fontSize = 62
        textLayer.font = "Impact" as CFString
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = CGColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0) // Amarillo neón
        textLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        textLayer.shadowOpacity = 0.9
        textLayer.shadowRadius = 8
        textLayer.shadowOffset = CGSize(width: 4, height: 4)
        textLayer.contentsScale = 2.0
        textLayer.frame = layer.bounds

        // Animación de impacto elástico (Bounce spring)
        let springAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        springAnim.beginTime = AVCoreAnimationBeginTimeAtZero + phraseStart
        springAnim.duration = 0.3
        springAnim.values = [0.8, 1.15, 0.95, 1.0]
        springAnim.keyTimes = [0.0, 0.4, 0.7, 1.0]
        springAnim.isRemovedOnCompletion = false
        springAnim.fillMode = .forwards
        textLayer.add(springAnim, forKey: "hormoziBounce")

        layer.addSublayer(textLayer)
    }

    private func buildMinimalDarkStyle(
        in layer: CALayer,
        chunk: [WordTimestamp],
        phraseStart: Double,
        renderSize: CGSize
    ) {
        // Fondo pastilla translúcida
        let bgLayer = CALayer()
        bgLayer.frame = layer.bounds
        bgLayer.backgroundColor = CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.75)
        bgLayer.cornerRadius = 24
        layer.addSublayer(bgLayer)

        let fullText = chunk.map { $0.word }.joined(separator: " ")
        let textLayer = CATextLayer()
        textLayer.string = fullText
        textLayer.fontSize = 44
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        textLayer.contentsScale = 2.0
        textLayer.frame = layer.bounds.insetBy(dx: 20, dy: 30)

        layer.addSublayer(textLayer)
    }

    private func buildKaraokeStyle(
        in layer: CALayer,
        chunk: [WordTimestamp],
        phraseStart: Double,
        renderSize: CGSize
    ) {
        let fullText = chunk.map { $0.word }.joined(separator: " ")

        // Capa base blanca/gris
        let baseTextLayer = CATextLayer()
        baseTextLayer.string = fullText
        baseTextLayer.fontSize = 48
        baseTextLayer.alignmentMode = .center
        baseTextLayer.foregroundColor = CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.8)
        baseTextLayer.contentsScale = 2.0
        baseTextLayer.frame = layer.bounds
        layer.addSublayer(baseTextLayer)

        // Capa iluminada con máscara progresiva
        let highlightTextLayer = CATextLayer()
        highlightTextLayer.string = fullText
        highlightTextLayer.fontSize = 48
        highlightTextLayer.alignmentMode = .center
        highlightTextLayer.foregroundColor = CGColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0)
        highlightTextLayer.contentsScale = 2.0
        highlightTextLayer.frame = layer.bounds

        let maskLayer = CALayer()
        maskLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        maskLayer.frame = CGRect(x: 0, y: 0, width: 0, height: layer.bounds.height)

        if let phraseEnd = chunk.last?.end {
            let duration = phraseEnd - phraseStart
            let progressAnim = CABasicAnimation(keyPath: "bounds.size.width")
            progressAnim.beginTime = AVCoreAnimationBeginTimeAtZero + phraseStart
            progressAnim.duration = duration
            progressAnim.fromValue = 0
            progressAnim.toValue = layer.bounds.width
            progressAnim.isRemovedOnCompletion = false
            progressAnim.fillMode = .forwards
            maskLayer.add(progressAnim, forKey: "karaokeFill")
        }

        highlightTextLayer.mask = maskLayer
        layer.addSublayer(highlightTextLayer)
    }

    private func groupWordsIntoPhrases(
        _ words: [WordTimestamp],
        maxWordsPerPhrase: Int
    ) -> [[WordTimestamp]] {
        var groups: [[WordTimestamp]] = []
        var current: [WordTimestamp] = []

        for word in words where !word.isDeleted {
            current.append(word)
            if current.count >= maxWordsPerPhrase {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }
}
