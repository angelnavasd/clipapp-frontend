import Foundation
import AVFoundation

#if canImport(WhisperKit)
import WhisperKit
#endif

public enum TranscriptionError: Error, LocalizedError {
    case modelNotFound
    case inferenceFailed(String)
    case emptyAudioData

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "No se pudo inicializar o descargar el modelo WhisperKit."
        case .inferenceFailed(let msg):
            return "Fallo en la transcripción CoreML: \(msg)"
        case .emptyAudioData:
            return "El buffer de audio está vacío."
        }
    }
}

/// Gestor de transcripción On-Device acelerada con WhisperKit y Apple Neural Engine
public final class WhisperTranscriptionManager {
    public static let shared = WhisperTranscriptionManager()

    private let audioAnalyzer = AudioLevelAnalyzer.shared
    private let fillerWords: Set<String> = [
        "ehhh", "eh", "mmm", "mm", "este", "o sea", "bueno", "tipo",
        "um", "uh", "like", "you know", "ah", "ajá"
    ]

    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    #endif

    public init() {}

    /// Inicializa el modelo WhisperKit (preferiblemente tiny / base para velocidad en ANE)
    public func initializeModel(modelVariant: String = "openai_whisper-base") async throws {
        #if canImport(WhisperKit)
        if whisperKit == nil {
            print("⏳ Inicializando WhisperKit (modelo: \(modelVariant))...")
            whisperKit = try await WhisperKit(model: modelVariant)
            print("✅ WhisperKit cargado exitosamente en CoreML/ANE.")
        }
        #endif
    }

    /// Transcribe las muestras de audio PCM generando timestamps por palabra enriquecidos con niveles de dB
    public func transcribe(
        audioSamples: [Float],
        videoId: String,
        language: String? = "es",
        videoDuration: Double,
        timeOffset: Double = 0.0,
        progress: ((Double) -> Void)? = nil
    ) async throws -> TranscriptPayload {
        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudioData
        }

        // 1. Análisis de niveles de energía con vDSP
        let energyWindows = audioAnalyzer.analyzeEnergyProfile(
            samples: audioSamples,
            sampleRate: 16000.0,
            windowDurationMs: 100.0
        )

        var rawWords: [WordTimestamp] = []

        #if canImport(WhisperKit)
        if whisperKit == nil {
            progress?(0.1)
            try await initializeModel(modelVariant: "openai_whisper-base")
        }

        guard let whisper = whisperKit else {
            throw TranscriptionError.modelNotFound
        }

        progress?(0.3)
        print("🎙️ Ejecutando WhisperKit para \(audioSamples.count) samples (\(videoDuration)s, offset: \(timeOffset)s)...")
        let langOption = (language == "auto" || language == nil) ? nil : language
        let transcriptionResults = try await whisper.transcribe(
            audioArray: audioSamples,
            decodeOptions: DecodingOptions(
                language: langOption,
                wordTimestamps: true
            )
        )
        progress?(0.8)

        for result in transcriptionResults {
            for segment in result.segments {
                if let words = segment.words, !words.isEmpty {
                    for w in words {
                        let cleanWord = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanWord.isEmpty else { continue }

                        let start = Double(w.start) + timeOffset
                        let end = Double(w.end) + timeOffset
                        let avgDb = audioAnalyzer.averageDb(in: energyWindows, start: Double(w.start), end: Double(w.end))
                        let isFiller = fillerWords.contains(cleanWord.lowercased())

                        rawWords.append(
                            WordTimestamp(
                                word: cleanWord,
                                start: (start * 100).rounded() / 100,
                                end: (end * 100).rounded() / 100,
                                db: avgDb,
                                isFiller: isFiller
                            )
                        )
                    }
                } else if !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let segmentWords = segment.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    let segDuration = Double(segment.end - segment.start)
                    let wordDuration = segDuration / Double(max(segmentWords.count, 1))

                    for (i, wordText) in segmentWords.enumerated() {
                        let relStart = Double(segment.start) + (Double(i) * wordDuration)
                        let relEnd = relStart + wordDuration
                        let start = relStart + timeOffset
                        let end = relEnd + timeOffset
                        let avgDb = audioAnalyzer.averageDb(in: energyWindows, start: relStart, end: relEnd)
                        let isFiller = fillerWords.contains(wordText.lowercased())

                        rawWords.append(
                            WordTimestamp(
                                word: wordText,
                                start: (start * 100).rounded() / 100,
                                end: (end * 100).rounded() / 100,
                                db: avgDb,
                                isFiller: isFiller
                            )
                        )
                    }
                }
            }
        }
        let previewSample = rawWords.prefix(15).map(\.word).joined(separator: " ")
        print("✅ Transcripción on-device completada: \(rawWords.count) palabras extraídas.")
        print("🎙️ [WhisperKit Muestra]: \"\(previewSample)...\"")
        #else
        throw TranscriptionError.modelNotFound
        #endif

        progress?(1.0)

        guard !rawWords.isEmpty else {
            throw TranscriptionError.inferenceFailed("No se detectó voz ni palabras comprensibles en el audio del video.")
        }

        // F1: adjuntar silencios vDSP para que el backend los salte (antes se calculaban y se tiraban)
        let gaps = audioAnalyzer.detectSilenceGaps(in: energyWindows, minDurationSeconds: 0.5)
        let silenceGaps = gaps.map { SilenceGap(start: $0.start, end: $0.end) }

        return TranscriptPayload(
            videoId: videoId,
            language: language,
            videoDuration: videoDuration,
            words: rawWords,
            silenceGaps: silenceGaps
        )
    }
}
