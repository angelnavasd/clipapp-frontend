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
        verticalPositionRatio: CGFloat = 0.70 // 0.0 arriba, 1.0 abajo
    ) -> CALayer {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.masksToBounds = true

        guard !words.isEmpty else { return parentLayer }

        // Agrupar palabras en oraciones/chunks de 3 a 5 palabras para legibilidad móvil
        let chunks = groupWordsIntoPhrases(words, maxWordsPerPhrase: 4)

        for chunk in chunks {
            guard let phraseStart = chunk.first?.start, let phraseEnd = chunk.last?.end else { continue }
            let phraseDuration = max(0.1, phraseEnd - phraseStart)

            let phraseLayer = CALayer()
            let phraseHeight: CGFloat = 200
            let phraseWidth: CGFloat = renderSize.width * 0.85
            let phraseY = renderSize.height * verticalPositionRatio

            phraseLayer.frame = CGRect(
                x: (renderSize.width - phraseWidth) / 2.0,
                y: phraseY,
                width: phraseWidth,
                height: phraseHeight
            )
            phraseLayer.opacity = 0.0

            // Animación de visibilidad sincronizada con los timestamps de la composición
            let showAnim = CAKeyframeAnimation(keyPath: "opacity")
            showAnim.beginTime = AVCoreAnimationBeginTimeAtZero + phraseStart
            showAnim.duration = phraseDuration
            showAnim.keyTimes = [0.0, 0.05, 0.95, 1.0]
            showAnim.values = [0.0, 1.0, 1.0, 0.0]
            showAnim.isRemovedOnCompletion = false
            showAnim.fillMode = .both
            phraseLayer.add(showAnim, forKey: "phraseVisibility")

            // Aplicar estilos específicos
            switch style {
            case .hormozi:
                buildHormoziStyle(
                    in: phraseLayer,
                    chunk: chunk,
                    highlightWords: highlightWords,
                    phraseStart: phraseStart
                )
            case .minimalDark:
                buildMinimalDarkStyle(
                    in: phraseLayer,
                    chunk: chunk,
                    phraseStart: phraseStart
                )
            case .karaoke:
                buildKaraokeStyle(
                    in: phraseLayer,
                    chunk: chunk,
                    phraseStart: phraseStart
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
        phraseStart: Double
    ) {
        guard let firstWord = chunk.first, let lastWord = chunk.last else { return }
        let fullText = chunk.map { $0.word }.joined(separator: " ")

        // 1. Fondo pill translúcido (idéntico al preview de la app)
        let bgLayer = CALayer()
        bgLayer.frame = layer.bounds
        bgLayer.backgroundColor = CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45)
        bgLayer.cornerRadius = 20
        layer.addSublayer(bgLayer)

        // 2. Capa base de texto blanco nítido con sombra de alto contraste
        let baseTextLayer = CATextLayer()
        baseTextLayer.string = fullText
        baseTextLayer.fontSize = 50
        baseTextLayer.font = "AvenirNext-Heavy" as CFString
        baseTextLayer.alignmentMode = .center
        baseTextLayer.isWrapped = true
        baseTextLayer.foregroundColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        baseTextLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        baseTextLayer.shadowOpacity = 0.95
        baseTextLayer.shadowRadius = 6
        baseTextLayer.shadowOffset = CGSize(width: 2, height: 2)
        baseTextLayer.contentsScale = 2.0
        baseTextLayer.frame = layer.bounds.insetBy(dx: 16, dy: 20)
        layer.addSublayer(baseTextLayer)

        // 3. Capa de texto amarillo vibrante para el resaltado progresivo palabra por palabra
        let highlightTextLayer = CATextLayer()
        highlightTextLayer.string = fullText
        highlightTextLayer.fontSize = 50
        highlightTextLayer.font = "AvenirNext-Heavy" as CFString
        highlightTextLayer.alignmentMode = .center
        highlightTextLayer.isWrapped = true
        highlightTextLayer.foregroundColor = CGColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1.0) // Amarillo vibrante #FFE600
        highlightTextLayer.contentsScale = 2.0
        highlightTextLayer.frame = layer.bounds.insetBy(dx: 16, dy: 20)

        // 4. Máscara de barrido progresivo sincronizada con las palabras de la frase
        let maskLayer = CALayer()
        maskLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        maskLayer.frame = CGRect(x: 0, y: 0, width: 0, height: layer.bounds.height)

        let totalDuration = max(0.1, lastWord.end - firstWord.start)
        let maskAnim = CABasicAnimation(keyPath: "bounds.size.width")
        maskAnim.beginTime = AVCoreAnimationBeginTimeAtZero + firstWord.start
        maskAnim.duration = totalDuration
        maskAnim.fromValue = 0
        maskAnim.toValue = layer.bounds.width
        maskAnim.isRemovedOnCompletion = false
        maskAnim.fillMode = .both
        maskLayer.add(maskAnim, forKey: "karaokeSweep")

        highlightTextLayer.mask = maskLayer
        layer.addSublayer(highlightTextLayer)
    }

    private func buildMinimalDarkStyle(
        in layer: CALayer,
        chunk: [WordTimestamp],
        phraseStart: Double
    ) {
        // Fondo pastilla translúcida
        let bgLayer = CALayer()
        bgLayer.frame = layer.bounds.insetBy(dx: 20, dy: 30)
        bgLayer.backgroundColor = CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.8)
        bgLayer.cornerRadius = 20
        layer.addSublayer(bgLayer)

        let fullText = chunk.map { $0.word }.joined(separator: " ")
        let textLayer = CATextLayer()
        textLayer.string = fullText
        textLayer.fontSize = 42
        textLayer.font = "HelveticaNeue-Bold" as CFString
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        textLayer.foregroundColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        textLayer.contentsScale = 2.0
        textLayer.frame = layer.bounds.insetBy(dx: 30, dy: 45)

        layer.addSublayer(textLayer)
    }

    private func buildKaraokeStyle(
        in layer: CALayer,
        chunk: [WordTimestamp],
        phraseStart: Double
    ) {
        let fullText = chunk.map { $0.word }.joined(separator: " ")

        // Capa base blanca con sombra
        let baseTextLayer = CATextLayer()
        baseTextLayer.string = fullText
        baseTextLayer.fontSize = 48
        baseTextLayer.font = "AvenirNext-Bold" as CFString
        baseTextLayer.alignmentMode = .center
        baseTextLayer.isWrapped = true
        baseTextLayer.foregroundColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)
        baseTextLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.9)
        baseTextLayer.shadowOpacity = 0.9
        baseTextLayer.shadowRadius = 6
        baseTextLayer.shadowOffset = CGSize(width: 2, height: 2)
        baseTextLayer.contentsScale = 2.0
        baseTextLayer.frame = layer.bounds
        layer.addSublayer(baseTextLayer)

        // Capa iluminada con máscara progresiva
        let highlightTextLayer = CATextLayer()
        highlightTextLayer.string = fullText
        highlightTextLayer.fontSize = 48
        highlightTextLayer.font = "AvenirNext-Bold" as CFString
        highlightTextLayer.alignmentMode = .center
        highlightTextLayer.isWrapped = true
        highlightTextLayer.foregroundColor = CGColor(red: 0.2, green: 0.85, blue: 1.0, alpha: 1.0)
        highlightTextLayer.contentsScale = 2.0
        highlightTextLayer.frame = layer.bounds

        let maskLayer = CALayer()
        maskLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        maskLayer.frame = CGRect(x: 0, y: 0, width: 0, height: layer.bounds.height)

        if let phraseEnd = chunk.last?.end {
            let duration = max(0.1, phraseEnd - phraseStart)
            let progressAnim = CABasicAnimation(keyPath: "bounds.size.width")
            progressAnim.beginTime = AVCoreAnimationBeginTimeAtZero + phraseStart
            progressAnim.duration = duration
            progressAnim.fromValue = 0
            progressAnim.toValue = layer.bounds.width
            progressAnim.isRemovedOnCompletion = false
            progressAnim.fillMode = .both
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
            // Si hay un salto de tiempo notable (>1.2s), cerrar la frase previa
            if let lastWord = current.last, (word.start - lastWord.end) > 1.2 {
                groups.append(current)
                current = []
            }

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
