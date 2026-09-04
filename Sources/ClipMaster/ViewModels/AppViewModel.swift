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
            return "Sintetizando 4 opciones de clips (Gemini Flash)..."
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
    @Published public var selectedWebcamCorner: WebcamCorner = .bottomRight
    @Published public var playerReloadToken: UUID = UUID()
    @Published public var detectedSpeakerCenterX: CGFloat = 0.5
    @Published public var detectedSpeakerCenterY: CGFloat = 0.5
    /// Ancho normalizado del rostro para zoom adaptativo (F4). nil = sin zoom.
    @Published public var detectedSpeakerFaceWidth: CGFloat? = nil
    /// Tracking facial por beat del clip seleccionado (F5: encuadre + export por tramo).
    @Published public var beatFaceTracks: [BeatFaceTrack] = []
    /// FIX-feed: framing resuelto POR CLIP. El feed mostraba todas las cards con el
    /// framing global del clip 1; ahora cada clip tiene el suyo (modo + centros por beat).
    @Published public var clipFramings: [String: ClipFraming] = [:]
    /// Clips cuyo player murió en negro: la card cae al poster con el error logueado.
    @Published public var failedClipIds: Set<String> = []

    /// Marca un clip como fallido en reproducción (hilo main).
    public func notePlaybackFailure(_ clipId: String) {
        self.failedClipIds.insert(clipId)
    }
    @Published public var isScreenShareDetected: Bool = false
    @Published public var selectedSubtitleStyle: SubtitleStyle = .hormozi
    @Published public var selectedSubtitleSize: SubtitleFontSize = .medium
    @Published public var showSafeZoneOverlay: Bool = true
    @Published public var subtitleVerticalOffset: CGFloat = 0.65
    @Published public var selectedLutPreset: LutPresetItem? = nil

    // MARK: - Catálogos de Assets
    @Published public var lutPresets: [LutPresetItem] = []

    // MARK: - Estado de Exportación
    @Published public var isExporting: Bool = false
    @Published public var exportProgress: Double = 0.0
    @Published public var exportedVideoURL: URL? = nil
    @Published public var errorMessage: String? = nil

    // MARK: - Servicios
    private let audioExtractionManager = AudioExtractionManager.shared
    private let transcriptionManager = WhisperTranscriptionManager.shared
    private let apiService = ClipsAPIService.shared
    private let renderEngine = VideoRenderEngine.shared
    // DEPRECATED: Vision on-device mataba al MediaAnalysisDaemon (XPC invalidated)
    // con ráfagas de requests. Fuera del pipeline; framing por Gemini vision.
    // Se conservan por si se necesitan como último recurso manual.
    private let faceTrackingService = FaceTrackingService.shared
    private let sceneLayoutEngine = SceneLayoutEngine.shared

    public init() {
        Task {
            await loadInitialAssets()
        }
    }

    public func loadInitialAssets() async {
        let luts = (try? await apiService.fetchLutPresets()) ?? []
        self.lutPresets = luts
        self.selectedLutPreset = luts.first
    }

    // MARK: - Ingesta de Video
    public func processPickedVideo(url: URL) async {
        self.localVideoURL = url
        self.errorMessage = nil
        self.failedClipIds = []
        self.clipFramings = [:]
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
            var transcript = try await transcriptionManager.transcribe(
                audioSamples: audioSamples,
                videoId: videoId,
                language: selectedLanguage,
                videoDuration: totalDuration,
                timeOffset: timeOffset
            ) { [weak self] p in
                Task { @MainActor in self?.processingProgress = 0.25 + (p * 0.4) }
            }
            // F1: adjuntar preferencia de duración del usuario y 4 opciones de clip
            transcript.targetDuration = targetDuration
            transcript.targetClipCount = 4

            // Escaneo de cambios de plano / cortes de escena (on-device, ~0.3s)
            print("🎬 [Step 2.5] Escaneando transiciones de escena en el video...")
            let sceneTrack = await FaceTrackService.track(in: asset, range: (timeOffset, timeOffset + effectiveDuration))
            let detectedSceneCuts = sceneTrack.hardCuts.map { Double(round($0 * 10) / 10) }
            transcript.sceneCuts = detectedSceneCuts
            print("✂️ [Step 2.5] \(detectedSceneCuts.count) cortes de escena detectados: \(detectedSceneCuts)")

            self.transcriptPayload = transcript
            print("✅ [Step 2] Transcripción completada: \(transcript.words.count) palabras (videoDuration=\(String(format: "%.1f", totalDuration))s, offset=\(String(format: "%.1f", timeOffset))s)")

            // PASO 3: Análisis editorial con Gemini Flash vía NestJS (Síntesis de 4 opciones de clips maestros)
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

            // PASO 3.5: Framing visual con Gemini (thumbs, sin Vision on-device)
            print("👁️ [Step 3.5] Analizando encuadre con Gemini vision...")
            self.selectedFramingMode = .autoFaceTrack

            if let firstClip = edl.clips.first {
                await self.resolveFraming(for: firstClip, asset: asset)
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

            // FIX-feed: resolver en fondo el framing de los demás clips para que
            // cada card tenga su propio encuadre (sin bloquear la navegación).
            let allClips = edl.clips
            let firstId = allClips.first?.id
            Task { [weak self] in
                guard let self else { return }
                await self.resolveRemainingClips(allClips, asset: asset, skipId: firstId)
            }
        } catch {
            print("❌ [Pipeline Falló]: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.navigationState = .home
        }
    }

    /// Construye una composición en memoria de AVFoundation para reproducir los saltos de tiempo (jump cuts) sin interrupciones
    public func buildComposition(
        for clip: ClipDecision,
        sourceURL: URL
    ) async throws -> AVMutableComposition {
        print("🔧 [buildComposition] Iniciando para clip '\(clip.title)' desde \(sourceURL.lastPathComponent)")
        
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

        let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        compVideoTrack.preferredTransform = transform

        let sourceDuration = (try? await asset.load(.duration).seconds) ?? 0.0
        var insertTime = CMTime.zero

        let segments: [(start: Double, end: Double)]
        if let beats = clip.storyBeats, !beats.isEmpty {
            segments = beats.map { ($0.start, $0.end) }
        } else {
            segments = VideoRenderEngine.shared.calculateKeepSegments(for: clip)
        }

        let finalSegments = segments.isEmpty
            ? [(clip.timeRange.start, clip.timeRange.end)]
            : segments

        for seg in finalSegments {
            // FIX "reproduce y se queda negro": un beat más allá del EOF generaba
            // un hueco vacío en la composición (negro eterno). Se salta, no se rellena.
            let s = max(0, min(seg.0, sourceDuration))
            let e = max(0, min(seg.1, sourceDuration))
            guard e - s > 0.05 else {
                print("⚠️ [buildComposition] segmento fuera de rango, saltado: \(String(format: "%.1f", seg.0))-\(String(format: "%.1f", seg.1)) (fuente: \(String(format: "%.1f", sourceDuration))s)")
                continue
            }
            let safeStart = s
            let segDur = e - s

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
                print("❌ [buildComposition] Fallo al insertar rango (\(safeStart) - \(safeStart + segDur)): \(error)")
            }
        }

        let totalCompDuration = insertTime.seconds
        guard totalCompDuration > 0.5 else {
            throw RenderError.compositionFailed("Composición vacía (<0.5s)")
        }

        return composition
    }

    public func setWebcamCorner(_ corner: WebcamCorner) {
        self.selectedWebcamCorner = corner
        let coords = corner.centerNormalized
        self.detectedSpeakerCenterX = coords.x
        self.detectedSpeakerCenterY = coords.y
        self.detectedSpeakerFaceWidth = nil
        self.playerReloadToken = UUID()
        print("🎯 [Encuadre] Webcam fijada a \(corner.rawValue): (\(coords.x), \(coords.y))")
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

        let rawWords = (transcriptPayload?.words ?? []).filter {
            $0.start >= (clip.timeRange.start - 1.0) && $0.end <= (clip.timeRange.end + 1.0)
        }
        let wordsForClip = mapWordsToCompositionTime(words: rawWords, for: clip)
        print("🎬 [Export] Subtítulos mapeados a la composición: \(wordsForClip.count) palabras.")
        if let first = wordsForClip.first, let last = wordsForClip.last {
            print("🎬 [Export] Rango de subtítulos: \(String(format: "%.2f", first.start))s a \(String(format: "%.2f", last.end))s")
        }

        let config = RenderConfiguration(
            clip: clip,
            framingMode: selectedFramingMode,
            subtitleStyle: selectedSubtitleStyle,
            words: wordsForClip,
            subtitleVerticalPosition: subtitleVerticalOffset,
            speakerCenterX: detectedSpeakerCenterX,
            speakerCenterY: detectedSpeakerCenterY,
            speakerFaceWidth: detectedSpeakerFaceWidth,
            perBeatCenters: perBeatCenters(for: clip)
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

    /// Framing on-device $0 (Vision mínima, sin red).
    /// 1 frame por beat -> FrameAnalysis -> ClipFraming en el store.
    /// Nunca crashea: si falla extracción o red (no hay), guarda neutros.
    /// Decide el modo de encuadre combinando `needsFace` del backend con lo visto.
    /// Guarda el resultado en `clipFramings[clip.id]`; si `updateGlobals`, además
    /// actualiza el estado global del editor.
    @discardableResult
    public func resolveFraming(for clip: ClipDecision, asset: AVAsset, updateGlobals: Bool = true) async -> ClipFraming {
        let beatRanges: [(start: Double, end: Double)]
        if let beats = clip.storyBeats, !beats.isEmpty {
            beatRanges = beats.map { ($0.start, $0.end) }
        } else {
            beatRanges = [(clip.timeRange.start, clip.timeRange.end)]
        }
        if updateGlobals { self.beatFaceTracks = [] }

        // Tracking facial denso y por beat (sin diluir muestras en tramos descartados)
        var centers: [BeatCenter] = []
        for r in beatRanges {
            let dur = r.end - r.start
            guard dur > 0.05 else { continue }
            let beatTrack = await FaceTrackService.track(in: asset, range: (r.start, r.end))
            // Verificar si hay cortes de toma dentro de este beat
            let cutsInBeat = beatTrack.hardCuts.filter { $0 > (r.start + 0.35) && $0 < (r.end - 0.35) }
            // Filtrar solo cambios de plano con salto visual significativo (evitar sobre-particionar por giros leves)
            let significantCuts = cutsInBeat.compactMap { cut -> (time: Double, shift: Double)? in
                let cBefore = FaceTrackService.center(at: cut - 0.15, in: beatTrack)
                let cAfter = FaceTrackService.center(at: cut + 0.15, in: beatTrack)
                let shift = hypot(cAfter.x - cBefore.x, cAfter.y - cBefore.y)
                return shift >= 0.18 ? (cut, shift) : nil
            }
            if let bestCut = significantCuts.max(by: { $0.shift < $1.shift }) {
                // Split limpio en 2 sub-tramos en el cambio de plano
                let mid1 = (r.start + bestCut.time) / 2.0
                let c1 = FaceTrackService.center(at: mid1, in: beatTrack)
                centers.append(BeatCenter(start: r.start, end: bestCut.time,
                    x: c1.x, y: c1.y, faceWidth: c1.w > 0 ? c1.w : nil))

                let mid2 = (bestCut.time + r.end) / 2.0
                let c2 = FaceTrackService.center(at: mid2, in: beatTrack)
                centers.append(BeatCenter(start: bestCut.time, end: r.end,
                    x: c2.x, y: c2.y, faceWidth: c2.w > 0 ? c2.w : nil))
            } else {
                let mid = (r.start + r.end) / 2.0
                let c = FaceTrackService.center(at: mid, in: beatTrack)
                centers.append(BeatCenter(start: r.start, end: r.end,
                    x: c.x, y: c.y, faceWidth: c.w > 0 ? c.w : nil))
            }
        }
        if centers.isEmpty {
            centers.append(BeatCenter(start: clip.timeRange.start, end: clip.timeRange.end, x: 0.5, y: 0.45, faceWidth: 0.25))
        }

        // F5-pro: Normalización y Estabilización por Escena (Locked Anchor)
        // Agrupa tramos continuos de la misma escena y fija la mediana de posición y zoom.
        let normalizedCenters = Self.normalizeSceneAnchors(centers)
        let mode: FramingMode = .autoFaceTrack
        let mid = normalizedCenters[normalizedCenters.count / 2]
        let center: (x: CGFloat, y: CGFloat) = (mid.x, mid.y)
        let framing = ClipFraming(mode: mode, centerX: center.x, centerY: center.y, faceWidth: mid.faceWidth, beatCenters: normalizedCenters)
        self.clipFramings[clip.id] = framing
        if updateGlobals { self.applyFraming(framing) }
        print("🎯 [Framing:Vision] clip=\(clip.id) modo=\(mode.rawValue) beats=\(normalizedCenters.count)")
        return framing
    }

    /// Normaliza los centros de encuadre por escena (Locked Anchor):
    /// Si múltiples tramos consecutivos corresponden a la misma toma del orador
    /// (distancia euclidiana < 0.18), se fija un anclaje único usando la mediana
    /// de posición (X, Y) y zoom (faceWidth).
    /// Esto elimina el bamboleo y saltos de zoom aleatorios entre cortes de la misma escena.
    nonisolated public static func normalizeSceneAnchors(_ centers: [BeatCenter]) -> [BeatCenter] {
        guard centers.count > 1 else { return centers }

        // 1. Agrupar tramos en clusters continuos de la misma escena
        var clusters: [[BeatCenter]] = []
        var currentCluster: [BeatCenter] = [centers[0]]

        for i in 1 ..< centers.count {
            let prev = currentCluster.last!
            let curr = centers[i]
            let dist = hypot(curr.x - prev.x, curr.y - prev.y)

            // Si el salto de posición es grande (>= 0.18, ej. webcam a plano completo), es otra escena
            if dist >= 0.18 {
                clusters.append(currentCluster)
                currentCluster = [curr]
            } else {
                currentCluster.append(curr)
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        // 2. Para cada cluster (escena continua), calcular el anclaje mediano estable
        var stabilized: [BeatCenter] = []
        for cluster in clusters {
            let sortedX = cluster.map(\.x).sorted()
            let sortedY = cluster.map(\.y).sorted()
            let medianX = sortedX[sortedX.count / 2]
            let medianY = sortedY[sortedY.count / 2]

            // Mediana de faceWidth (zoom bloqueado)
            let widths = cluster.compactMap(\.faceWidth).sorted()
            let medianW: CGFloat? = widths.isEmpty ? nil : widths[widths.count / 2]

            for item in cluster {
                stabilized.append(BeatCenter(
                    start: item.start,
                    end: item.end,
                    x: medianX,
                    y: medianY,
                    faceWidth: medianW
                ))
            }
        }
        return stabilized
    }

    /// Parsea el índice de beat del id "b{i}t0".
    nonisolated static func beatIndex(of id: String) -> Int? {
        guard id.hasPrefix("b"), let t = id.firstIndex(of: "t") else { return nil }
        return Int(id[id.index(after: id.startIndex)..<t])
    }

    /// Aplica un framing guardado al estado global del editor.
    public func applyFraming(_ framing: ClipFraming) {
        self.selectedFramingMode = framing.mode
        self.detectedSpeakerCenterX = framing.centerX
        self.detectedSpeakerCenterY = framing.centerY
        self.detectedSpeakerFaceWidth = framing.faceWidth
    }

    /// FIX-feed: resuelve en fondo el framing de todos los clips del EDL para que
    /// cada card tenga su propio encuadre (no el del clip 1). Corre tras navegar al feed.
    public func resolveRemainingClips(_ clips: [ClipDecision], asset: AVAsset, skipId: String? = nil) async {
        for clip in clips where clip.id != skipId && self.clipFramings[clip.id] == nil {
            await self.resolveFraming(for: clip, asset: asset, updateGlobals: false)
        }
        print("🎯 [Framing] resolución en fondo completada para \(clips.count) clips")
    }

    /// FIX-feed: Quick Export con el framing correcto del clip (antes exportaba con
    /// el framing global del clip 1 o con valores stale).
    public func quickExport(_ clip: ClipDecision) async {
        self.selectedClip = clip
        if let stored = clipFramings[clip.id] {
            self.applyFraming(stored)
        } else if let url = localVideoURL {
            let asset = AVAsset(url: url)
            await self.resolveFraming(for: clip, asset: asset, updateGlobals: true)
        }
        await self.exportCurrentClip()
    }

    /// Selecciona un clip del feed, navega al editor y ejecuta el tracking facial para recortar y centrar el rostro
    public func selectClip(_ clip: ClipDecision) {
        self.selectedClip = clip
        self.navigationState = .editor
        triggerHapticFeedback(type: .light)

        Task {
            guard let url = localVideoURL else { return }
            let asset = AVAsset(url: url)
            await self.resolveFraming(for: clip, asset: asset)
        }
    }

    /// F5: centros por beat en tiempo-source para el export (un transform por tramo).
    /// Usa el framing guardado del clip; si el usuario cambió de modo manualmente
    /// en el editor, se respeta el modo manual con el centro único (nil).
    /// FIX: un beat sin cara va al centro SIN zoom (mostrar la pantalla tal cual),
    /// no a la posición de la cara del hook (eso mostraba un trozo random de pantalla).
    public func perBeatCenters(for clip: ClipDecision) -> [(start: Double, end: Double, x: CGFloat, y: CGFloat, faceWidth: CGFloat?)]? {
        if let stored = clipFramings[clip.id],
           stored.mode == .autoFaceTrack, selectedFramingMode == .autoFaceTrack,
           let beats = clip.storyBeats, !beats.isEmpty,
           !stored.beatCenters.isEmpty {
            return stored.beatCenters.map { ($0.start, $0.end, $0.x, $0.y, $0.faceWidth) }
        }
        guard selectedFramingMode == .autoFaceTrack,
              let beats = clip.storyBeats, !beats.isEmpty,
              beatFaceTracks.count == beats.count else { return nil }
        return zip(beats, beatFaceTracks).map { beat, track in
            if let face = track.averageFace, track.confidence >= 0.3 {
                return (beat.start, beat.end, face.midX, face.midY, face.width)
            }
            return (beat.start, beat.end, 0.5, 0.5, nil)
        }
    }

    /// Modo de encuadre de un clip (guardado; auto hasta que se resuelva).
    public func framingMode(for clip: ClipDecision) -> FramingMode {
        clipFramings[clip.id]?.mode ?? .autoFaceTrack
    }

    /// F5-fix: centro de encuadre para un instante de la COMPOSICIÓN (preview en vivo).
    /// Mapea tiempo-comp -> tiempo-source -> beat -> centro de ese beat.
    public func framingCenter(atCompTime compTime: Double, for clip: ClipDecision) -> (x: CGFloat, y: CGFloat, faceWidth: CGFloat?) {
        // Override manual del editor: si el modo global difiere del guardado, mandan los globales.
        if clip.id == selectedClip?.id,
           let stored = clipFramings[clip.id],
           selectedFramingMode != stored.mode {
            return (detectedSpeakerCenterX, detectedSpeakerCenterY, detectedSpeakerFaceWidth)
        }
        guard let stored = clipFramings[clip.id] else {
            // Aún sin resolver (fondo en curso): centro neutro, no el de otro clip.
            return (0.5, 0.5, nil)
        }
        guard stored.mode == .autoFaceTrack,
              let beats = clip.storyBeats, !beats.isEmpty,
              !stored.beatCenters.isEmpty else {
            return (stored.centerX, stored.centerY, stored.faceWidth)
        }
        let sourceTime = mapCompositionTime(compTime, for: clip)
        if let bc = stored.beatCenters.first(where: { sourceTime >= $0.start && sourceTime <= $0.end }) {
            return (bc.x, bc.y, bc.faceWidth)
        }
        return (stored.centerX, stored.centerY, stored.faceWidth)
    }

    /// Atajo para el clip seleccionado (editor).
    public func framingCenter(atCompTime compTime: Double) -> (x: CGFloat, y: CGFloat, faceWidth: CGFloat?) {
        guard let clip = selectedClip else {
            return (detectedSpeakerCenterX, detectedSpeakerCenterY, detectedSpeakerFaceWidth)
        }
        return framingCenter(atCompTime: compTime, for: clip)
    }

    /// Mapea los timestamps absolutos del video original a la línea de tiempo de la composición exportada (0...duración neta)
    public func mapWordsToCompositionTime(words: [WordTimestamp], for clip: ClipDecision) -> [WordTimestamp] {
        let keepSegments = VideoRenderEngine.shared.calculateKeepSegments(for: clip)
        var mappedWords: [WordTimestamp] = []
        var compOffset: Double = 0.0

        for seg in keepSegments {
            let segDuration = seg.end - seg.start
            let segWords = words.filter { $0.start >= (seg.start - 0.2) && $0.end <= (seg.end + 0.2) }
            for w in segWords {
                let mappedStart = compOffset + max(0, w.start - seg.start)
                let mappedEnd = compOffset + min(segDuration, w.end - seg.start)
                if mappedEnd > mappedStart {
                    mappedWords.append(WordTimestamp(
                        word: w.word,
                        start: mappedStart,
                        end: mappedEnd,
                        db: w.db,
                        isFiller: w.isFiller,
                        isDeleted: w.isDeleted
                    ))
                }
            }
            compOffset += segDuration
        }
        return mappedWords
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
        let minStart = clip.timeRange.start - 1.0
        let maxEnd = clip.timeRange.end + 1.0

        let clipWords: [WordTimestamp] = payload.words.filter { w in
            w.start >= minStart && w.end <= maxEnd
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
