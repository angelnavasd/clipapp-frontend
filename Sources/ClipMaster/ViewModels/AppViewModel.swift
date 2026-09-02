import Foundation
import SwiftUI
import AVFoundation
import PhotosUI

public enum AppNavigationState: Hashable {
    case home
    case videoConfirmation
    case processing
    case clipsFeed
    case editor
}

public enum ProcessingStep: Int, CaseIterable {
    case extractingAudio = 0
    case transcribingOnDevice = 1
    case analyzingWithGemini = 2
    case preparingPreviews = 3

    public var title: String {
        switch self {
        case .extractingAudio:
            return "Extrayendo audio local..."
        case .transcribingOnDevice:
            return "Transcribiendo audio on-device (WhisperKit)..."
        case .analyzingWithGemini:
            return "Sintetizando 2 clips maestros (Gemini Flash)..."
        case .preparingPreviews:
            return "Preparando previsualizaciones 9:16..."
        }
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    // MARK: - Estado de Navegación
    @Published public var navigationState: AppNavigationState = .home
    @Published public var currentProcessingStep: ProcessingStep = .extractingAudio
    @Published public var processingProgress: Double = 0.0

    // MARK: - Ajustes de Ingesta
    @Published public var targetDuration: String = "Auto (20-40s)"
    @Published public var selectedLanguage: String = "es"

    // MARK: - Datos del Proyecto Actual
    @Published public var selectedVideoItem: PhotosPickerItem? = nil
    @Published public var localVideoURL: URL? = nil
    @Published public var videoDuration: Double = 0.0
    @Published public var transcriptPayload: TranscriptPayload? = nil
    @Published public var edlResponse: EDLResponse? = nil

    // MARK: - Clip Seleccionado y Configuración del Editor
    @Published public var selectedClip: ClipDecision? = nil
    @Published public var activeEditorTab: Int = 0 // 0: Trim/Text, 1: Framing, 2: Subtitles, 3: Audio/Vibe
    @Published public var selectedFramingMode: FramingMode = .autoFaceTrack
    @Published public var detectedSpeakerCenterX: CGFloat = 0.5
    @Published public var detectedSpeakerCenterY: CGFloat = 0.5
    @Published public var isScreenShareDetected: Bool = false
    @Published public var selectedSubtitleStyle: SubtitleStyle = .hormozi
    @Published public var selectedSubtitleSize: SubtitleFontSize = .medium
    @Published public var showSafeZoneOverlay: Bool = true
    @Published public var subtitleVerticalOffset: CGFloat = 0.65
    @Published public var enableAutoDucking: Bool = true
    @Published public var selectedMusicTrack: MusicTrackItem? = nil
    @Published public var selectedLutPreset: LutPresetItem? = nil

    // MARK: - Catálogos de Assets
    @Published public var musicTracks: [MusicTrackItem] = []
    @Published public var lutPresets: [LutPresetItem] = []

    // MARK: - Estado de Exportación
    @Published public var isExporting: Bool = false
    @Published public var exportProgress: Double = 0.0
    @Published public var exportedVideoURL: URL? = nil
    @Published public var errorMessage: String? = nil

    // MARK: - Servicios
    private let audioExtractionManager = AudioExtractionManager.shared
    private let transcriptionManager = WhisperTranscriptionManager.shared
    private let faceTrackingService = FaceTrackingService.shared
    private let apiService = ClipsAPIService.shared
    private let renderEngine = VideoRenderEngine.shared

    public init() {
        Task {
            await loadInitialAssets()
        }
    }

    public func loadInitialAssets() async {
        do {
            async let music = apiService.fetchMusicCatalog()
            async let luts = apiService.fetchLutPresets()
            self.musicTracks = (try? await music) ?? []
            self.lutPresets = (try? await luts) ?? []
            self.selectedMusicTrack = musicTracks.first
            self.selectedLutPreset = lutPresets.first
        }
    }

    // MARK: - Ingesta de Video
    public func processPickedVideo(url: URL) async {
        self.localVideoURL = url
        self.errorMessage = nil
        let asset = AVURLAsset(url: url)
        if let dur = try? await asset.load(.duration).seconds {
            self.videoDuration = dur
        }
        // Navegar a la pantalla intermedia para confirmar y recortar el rango si se desea
        self.navigationState = .videoConfirmation
    }

    // MARK: - Pipeline Completo de Procesamiento (con soporte de rango opcional)
    public func startPipeline(forTrimmedRange timeRange: TimeRange? = nil) async {
        guard let url = localVideoURL else { return }
        self.navigationState = .processing
        self.errorMessage = nil
        self.processingProgress = 0.0

        let asset = AVURLAsset(url: url)
        do {
            let totalDuration = try await asset.load(.duration).seconds
            let effectiveDuration = timeRange?.duration ?? totalDuration
            let timeOffset = timeRange?.start ?? 0.0

            // PASO 1: Extracción de audio (parcial si fue recortado)
            print("🚀 [Step 1] Extrayendo audio PCM para \(url.lastPathComponent) (duración efectiva: \(effectiveDuration)s)...")
            triggerHapticFeedback()
            self.currentProcessingStep = .extractingAudio
            let audioSamples = try await audioExtractionManager.extractPCMFloatArray(
                from: asset,
                timeRange: timeRange
            ) { [weak self] p in
                Task { @MainActor in self?.processingProgress = p * 0.25 }
            }
            print("✅ [Step 1] Audio extraído con éxito: \(audioSamples.count) samples.")

            // PASO 2: Transcripción on-device (WhisperKit + vDSP)
            print("🎙️ [Step 2] Iniciando WhisperKit on-device (idioma: \(selectedLanguage))...")
            triggerHapticFeedback()
            self.currentProcessingStep = .transcribingOnDevice
            let videoId = "local-\(UUID().uuidString.prefix(8))"
            let transcript = try await transcriptionManager.transcribe(
                audioSamples: audioSamples,
                videoId: videoId,
                language: selectedLanguage,
                videoDuration: totalDuration,
                timeOffset: timeOffset
            ) { [weak self] p in
                Task { @MainActor in self?.processingProgress = 0.25 + (p * 0.4) }
            }
            self.transcriptPayload = transcript
            print("✅ [Step 2] Transcripción completada: \(transcript.words.count) palabras (videoDuration=\(String(format: "%.1f", totalDuration))s, offset=\(String(format: "%.1f", timeOffset))s)")

            // PASO 3: Análisis editorial con Gemini Flash vía NestJS (Síntesis de 2 clips maestros)
            print("✨ [Step 3] Contactando backend en \(ClipsAPIService.shared.baseURL)...")
            triggerHapticFeedback()
            self.currentProcessingStep = .analyzingWithGemini
            self.processingProgress = 0.75
            let edl = try await apiService.analyzeTranscript(payload: transcript)
            self.edlResponse = edl
            print("✅ [Step 3] Análisis completado: \(edl.clips.count) clips recibidos.")

            guard !edl.clips.isEmpty else {
                print("⚠️ [Pipeline] No se pudieron extraer clips virales de este segmento.")
                self.errorMessage = edl.message ?? "No se detectó suficiente contenido hablado con sentido en este fragmento. Prueba seleccionando otra sección del video donde se hable claramente."
                self.navigationState = .videoConfirmation
                return
            }

            // PASO 4: Preparación de previsualizaciones
            print("🎬 [Step 4] Preparando previsualizaciones...")
            triggerHapticFeedback()
            self.currentProcessingStep = .preparingPreviews
            self.processingProgress = 1.0

            try? await Task.sleep(nanoseconds: 500_000_000)

            // Navegar al feed de clips
            if let firstClip = edl.clips.first {
                self.selectedClip = firstClip
            }
            print("🎉 [Pipeline Completado] Navegando a Clips Feed con \(edl.clips.count) clips.")
            self.navigationState = .clipsFeed
        } catch {
            print("❌ [Pipeline Falló]: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.navigationState = .home
        }
    }

    /// Construye una composición en memoria de AVFoundation para reproducir los saltos de tiempo (jump cuts) sin interrupciones
    public func buildComposition(for clip: ClipDecision, sourceURL: URL) async throws -> AVMutableComposition {
        print("🔧 [buildComposition] Iniciando para clip '\(clip.title)' desde \(sourceURL.lastPathComponent)")
        print("🔧 [buildComposition] clip.storyBeats count = \(clip.storyBeats?.count ?? 0), clip.cutSegments count = \(clip.cutSegments.count)")
        
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            print("❌ [buildComposition] No se encontró pista de video en el asset")
            throw RenderError.noVideoTrack
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RenderError.compositionFailed("No se pudo crear pista de video")
        }

        let compAudioTrack = audioTrack != nil
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        // Transferir preferredTransform para evitar pantalla negra o rotación incorrecta
        let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        compVideoTrack.preferredTransform = transform

        let sourceDuration = (try? await asset.load(.duration).seconds) ?? 0.0
        print("🔧 [buildComposition] Duración del asset original: \(String(format: "%.1f", sourceDuration))s")
        
        var insertTime = CMTime.zero

        // Obtener segmentos: beats o keepSegments
        let segments: [(start: Double, end: Double)]
        if let beats = clip.storyBeats, !beats.isEmpty {
            segments = beats.map { ($0.start, $0.end) }
            print("🔧 [buildComposition] Usando \(beats.count) storyBeats como segmentos")
        } else {
            segments = VideoRenderEngine.shared.calculateKeepSegments(for: clip)
            print("🔧 [buildComposition] Usando \(segments.count) keepSegments (sin storyBeats)")
        }

        // Si la lista de segmentos está vacía, usar el rango completo del clip como salvaguarda
        let finalSegments = segments.isEmpty
            ? [(clip.timeRange.start, clip.timeRange.end)]
            : segments
        
        print("🔧 [buildComposition] Total \(finalSegments.count) segmentos a insertar:")
        for (i, seg) in finalSegments.enumerated() {
            print("  📐 Segmento \(i+1): \(String(format: "%.1f", seg.0))s - \(String(format: "%.1f", seg.1))s (dur=\(String(format: "%.1f", seg.1 - seg.0))s)")
        }

        for seg in finalSegments {
            let safeStart = max(0, min(seg.0, sourceDuration))
            let safeEnd = max(safeStart + 0.1, min(seg.1, sourceDuration))
            let segDur = safeEnd - safeStart
            guard segDur > 0.05 else {
                print("⚠️ [buildComposition] Saltando segmento demasiado corto: \(segDur)s")
                continue
            }

            let startCM = CMTime(seconds: safeStart, preferredTimescale: 600)
            let durCM = CMTime(seconds: segDur, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startCM, duration: durCM)

            do {
                try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: insertTime)
                if let aTrack = audioTrack, let compATrack = compAudioTrack {
                    try compATrack.insertTimeRange(timeRange, of: aTrack, at: insertTime)
                }
                insertTime = CMTimeAdd(insertTime, durCM)
            } catch {
                print("❌ [buildComposition] Fallo al insertar rango (\(safeStart) - \(safeEnd)): \(error)")
            }
        }

        let totalCompDuration = insertTime.seconds
        print("✅ [buildComposition] Composición lista: \(String(format: "%.1f", totalCompDuration))s netos (vs \(String(format: "%.1f", sourceDuration))s original)")
        
        guard totalCompDuration > 0.5 else {
            throw RenderError.compositionFailed("Composición vacía (<0.5s)")
        }

        return composition
    }

    // MARK: - Acciones del Editor
    public func selectClipForEditing(_ clip: ClipDecision) {
        self.selectClip(clip)
    }

    public func deleteWordFromCurrentClip(_ word: WordTimestamp) {
        guard var clip = selectedClip, var transcript = transcriptPayload else { return }

        // 1. Marcar palabra como borrada en el transcript
        if let idx = transcript.words.firstIndex(where: { $0.id == word.id }) {
            var updatedWord = transcript.words[idx]
            updatedWord.isDeleted = true
            transcript.words[idx] = updatedWord
            self.transcriptPayload = transcript
        }

        // 2. Agregar segmento a descartar en el clip (corte de video automático)
        let cut = CutSegment(start: word.start, end: word.end, reason: "user_deleted_word")
        clip.cutSegments.append(cut)
        self.selectedClip = clip

        triggerHapticFeedback(type: .medium)
    }

    public func exportCurrentClip() async {
        guard let clip = selectedClip, let videoURL = localVideoURL else { return }

        self.isExporting = true
        self.exportProgress = 0.0

        let asset = AVURLAsset(url: videoURL)
        let outputFileName = "Export_\(clip.id)_\(Int(Date().timeIntervalSince1970)).mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)

        let wordsForClip = (transcriptPayload?.words ?? []).filter {
            $0.start >= clip.timeRange.start && $0.end <= clip.timeRange.end
        }

        let config = RenderConfiguration(
            clip: clip,
            framingMode: selectedFramingMode,
            subtitleStyle: selectedSubtitleStyle,
            words: wordsForClip,
            musicTrackURL: nil,
            enableAutoDucking: enableAutoDucking,
            subtitleVerticalPosition: subtitleVerticalOffset,
            speakerCenterX: detectedSpeakerCenterX,
            speakerCenterY: detectedSpeakerCenterY
        )

        do {
            try await renderEngine.renderAndExport(
                sourceAsset: asset,
                config: config,
                outputURL: outputURL
            ) { [weak self] p in
                Task { @MainActor in self?.exportProgress = p }
            }

            self.exportedVideoURL = outputURL
            self.isExporting = false
            triggerHapticFeedback(type: .success)
        } catch {
            self.isExporting = false
            self.errorMessage = "Fallo en la exportación: \(error.localizedDescription)"
        }
    }

    /// Selecciona un clip del feed, navega al editor y ejecuta el tracking facial para recortar y centrar el rostro
    public func selectClip(_ clip: ClipDecision) {
        self.selectedClip = clip
        self.navigationState = .editor
        triggerHapticFeedback(type: .light)

        Task {
            guard let url = localVideoURL else { return }
            let asset = AVAsset(url: url)
            let (_, avgFace, isScreenShare) = (try? await faceTrackingService.trackSpeaker(in: asset, timeRange: clip.timeRange)) ?? ([], nil, false)

            if let avg = avgFace {
                self.detectedSpeakerCenterX = avg.midX
                self.detectedSpeakerCenterY = avg.midY
                print("🎯 Rostro fijado en X: \(avg.midX), Y: \(avg.midY)")
            }

            self.isScreenShareDetected = isScreenShare
            if isScreenShare {
                self.selectedFramingMode = .splitScreen
                print("💡 Modo automático fijado a Split-Screen por detección de pantalla de computadora.")
            } else {
                self.selectedFramingMode = .autoFaceTrack
            }
        }
    }

    /// Mapea el tiempo del reproductor (0...duración neta) al segundo real del video original
    public func mapCompositionTime(_ compTime: Double, for clip: ClipDecision) -> Double {
        if let beats = clip.storyBeats, !beats.isEmpty {
            var accumulated: Double = 0.0
            for beat in beats {
                if compTime <= (accumulated + beat.duration) {
                    let offsetInBeat = max(0, compTime - accumulated)
                    return beat.start + offsetInBeat
                }
                accumulated += beat.duration
            }
            return beats.last?.end ?? clip.timeRange.end
        } else {
            let keepSegments = VideoRenderEngine.shared.calculateKeepSegments(for: clip)
            if !keepSegments.isEmpty {
                var accumulated: Double = 0.0
                for seg in keepSegments {
                    let segDur = seg.end - seg.start
                    if compTime <= (accumulated + segDur) {
                        let offsetInSeg = max(0, compTime - accumulated)
                        return seg.start + offsetInSeg
                    }
                    accumulated += segDur
                }
            }
            return clip.timeRange.start + compTime
        }
    }

    /// Devuelve la palabra activa en el segundo actual de reproducción y las palabras de contexto adyacentes para el subtítulo
    public func activeWords(at time: Double) -> (activeWord: WordTimestamp?, contextWords: [WordTimestamp]) {
        guard let clip = selectedClip, let payload = transcriptPayload else {
            return (nil, [])
        }

        let realVideoTime = mapCompositionTime(time, for: clip)

        let clipWords = payload.words.filter { w in
            w.start >= (clip.timeRange.start - 1.0) && w.end <= (clip.timeRange.end + 1.0)
        }

        guard !clipWords.isEmpty else { return (nil, []) }

        // Si el tiempo coincide con una palabra activa
        if let idx = clipWords.firstIndex(where: { realVideoTime >= $0.start && realVideoTime <= $0.end }) {
            let active = clipWords[idx]
            let start = max(0, idx - 1)
            let end = min(clipWords.count, idx + 3)
            return (active, Array(clipWords[start..<end]))
        }

        // Si está en una micropausa, mantener visible la palabra recién dicha
        if let lastIdx = clipWords.lastIndex(where: { $0.end <= realVideoTime && (realVideoTime - $0.end) < 1.2 }) {
            let active = clipWords[lastIdx]
            let start = max(0, lastIdx - 1)
            let end = min(clipWords.count, lastIdx + 3)
            return (active, Array(clipWords[start..<end]))
        }

        // Si estamos en la previa antes de la primera palabra
        if let first = clipWords.first, realVideoTime < first.start {
            let end = min(clipWords.count, 3)
            return (first, Array(clipWords[0..<end]))
        }

        return (nil, [])
    }

    public enum HapticFeedbackType {
        case success
        case warning
        case error
        case light
        case medium
        case heavy
    }

    public func triggerHapticFeedback(type: HapticFeedbackType = .success) {
        #if os(iOS)
        switch type {
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }
        #endif
    }
}
