import SwiftUI
import AVKit

public struct VideoCanvasView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isPlaying: Bool
    @Binding var currentPlaybackTime: Double
    @Binding var totalDuration: Double
    @Binding var seekActionTime: Double?

    @State private var player: AVPlayer? = nil
    @State private var timeObserverToken: Any? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var sourceSize: CGSize? = nil

    public init(
        viewModel: AppViewModel,
        isPlaying: Binding<Bool>,
        currentPlaybackTime: Binding<Double>,
        totalDuration: Binding<Double>,
        seekActionTime: Binding<Double?>
    ) {
        self.viewModel = viewModel
        self._isPlaying = isPlaying
        self._currentPlaybackTime = currentPlaybackTime
        self._totalDuration = totalDuration
        self._seekActionTime = seekActionTime
    }

    public var body: some View {
        ZStack {
            // Contenedor 9:16 del Video Principal
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black)
                .aspectRatio(9/16, contentMode: .fit)
                .overlay(
                    Group {
                        if let player = player {
                            framedPlayer(player)
                        } else {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                Text("Cargando video...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                )
                .onTapGesture {
                    togglePlayPause()
                }

            // Filtro / LUT preview overlay
            if let lut = viewModel.selectedLutPreset {
                Color(hex: lut.thumbnailColor)
                    .opacity(0.12)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }

            // Subtítulos Dinámicos (Arrastrables verticalmente con flujo multilínea natural y restricción de ancho)
            GeometryReader { geo in
                let videoWidth = min(geo.size.width, geo.size.height * 9.0 / 16.0)
                let maxSubtitleWidth = max(140.0, videoWidth * 0.84)
                let currentY = geo.size.height * viewModel.subtitleVerticalOffset + dragOffset.height

                VStack {
                    subtitlePreviewBadge(maxWidth: maxSubtitleWidth)
                        .position(x: geo.size.width / 2.0, y: max(50, min(geo.size.height - 50, currentY)))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    let newY = currentY
                                    viewModel.subtitleVerticalOffset = min(max(newY / geo.size.height, 0.2), 0.82)
                                    dragOffset = .zero
                                    viewModel.triggerHapticFeedback(type: .light)
                                }
                        )
                }
            }

            // Botón central flotante de Play cuando está pausado
            if !isPlaying {
                Button(action: togglePlayPause) {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .offset(x: 2)
                        )
                }
            }

            // Badge superior discreto con el modo de encuadre activo
            VStack {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 10))
                        Text(viewModel.selectedFramingMode.rawValue)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())

                    Spacer()
                }
                .padding(12)

                Spacer()
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                player?.play()
            } else {
                player?.pause()
            }
        }
        .onChange(of: seekActionTime) { _, target in
            if let t = target {
                seek(to: t)
                seekActionTime = nil
            }
        }
        .onChange(of: viewModel.selectedFramingMode) { _, _ in
            setupPlayer()
        }
        .onChange(of: viewModel.playerReloadToken) { _, _ in
            setupPlayer()
        }
    }

    // MARK: - Configuración de Reproductor
    /// Helper separado para no saturar el type-checker del body.
    /// F5-fix: el centro sigue al beat actual (igual que el export por tramos).
    private func framedPlayer(_ player: AVPlayer) -> SmartFramedPlayerView {
        let c = viewModel.framingCenter(atCompTime: currentPlaybackTime)
        return SmartFramedPlayerView(
            player: player,
            mode: viewModel.selectedFramingMode,
            speakerCenterX: c.x,
            speakerCenterY: c.y,
            cornerRadius: 22,
            sourceSize: sourceSize,
            speakerFaceWidth: c.faceWidth
        )
    }

    private func setupPlayer() {
        guard let url = viewModel.localVideoURL, let clip = viewModel.selectedClip else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        Task {
            var playerItem: AVPlayerItem? = nil
            var effectiveDuration = max(1.0, clip.netDuration)
            var isComposition = false

            // F4: conocer el tamaño natural para preview idéntico al export (corregido por rotación)
            if let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
               let naturalSize = try? await track.load(.naturalSize) {
                let tx = (try? await track.load(.preferredTransform)) ?? .identity
                let oriented = FaceCropCalculator.orientedSize(naturalSize: naturalSize, preferredTransform: tx)
                await MainActor.run { self.sourceSize = oriented }
            }

            do {
                let comp = try await viewModel.buildComposition(for: clip, sourceURL: url)
                let compDur = (try? await comp.load(.duration).seconds) ?? 0.0
                if compDur > 0.5 {
                    playerItem = AVPlayerItem(asset: comp)
                    effectiveDuration = compDur
                    isComposition = true
                    print("🎬 [Editor] Composición creada con éxito (\(String(format: "%.1f", compDur))s)")
                }
            } catch {
                print("❌ [Editor] Error construyendo composición: \(error). Usando fallback directo.")
            }

            let p: AVPlayer
            if let item = playerItem {
                p = AVPlayer(playerItem: item)
                await p.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                print("⚠️ [Editor] Usando reproductor directo de video original")
                let asset = AVURLAsset(url: url)
                let item = AVPlayerItem(asset: asset)
                p = AVPlayer(playerItem: item)
                let startTime = CMTime(seconds: clip.timeRange.start, preferredTimescale: 600)
                await p.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }

            p.actionAtItemEnd = .none
            p.volume = 1.0
            p.isMuted = false

            await MainActor.run {
                self.currentPlaybackTime = 0.0
                self.totalDuration = effectiveDuration
                self.player = p
                p.play()
                self.isPlaying = true

                let interval = CMTime(value: 1, timescale: 30)
                self.timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
                    guard let _ = p else { return }
                    self.currentPlaybackTime = time.seconds
                }

                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: p.currentItem,
                    queue: .main
                ) { _ in
                    if isComposition {
                        p.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    } else {
                        let startTime = CMTime(seconds: clip.timeRange.start, preferredTimescale: 600)
                        p.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    self.currentPlaybackTime = 0.0
                    p.play()
                }

                // Diagnóstico: loguear el error real si el item muere en negro
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime,
                    object: p.currentItem,
                    queue: .main
                ) { note in
                    let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)
                    print("❌ [Editor] ITEM FALLÓ: \(err?.domain ?? "?") \(err?.code ?? -1) \(err?.localizedDescription ?? "sin descripción")")
                }
            }
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player?.pause()
        player = nil
    }

    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        viewModel.triggerHapticFeedback(type: .light)
    }

    private func seek(to seconds: Double) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentPlaybackTime = seconds
    }

    // MARK: - Subtítulos Sincronizados con Flujo de Texto Continuo
    @ViewBuilder
    private func subtitlePreviewBadge(maxWidth: CGFloat) -> some View {
        let (activeWord, contextWords) = viewModel.activeWords(at: currentPlaybackTime)

        if !contextWords.isEmpty {
            let baseSize = viewModel.selectedSubtitleSize.pointSize

            contextWords.enumerated().reduce(Text("")) { result, item in
                let (index, w) = item
                let isActive = (w.id == activeWord?.id)
                let isPast = w.end <= currentPlaybackTime

                let wordColor: Color
                let wordWeight: Font.Weight

                switch viewModel.selectedSubtitleStyle {
                case .hormozi:
                    wordColor = isActive ? Color(red: 1.0, green: 0.9, blue: 0.0) : .white
                    wordWeight = .black
                case .minimalDark:
                    wordColor = isActive ? Color(red: 0.3, green: 0.85, blue: 1.0) : .white
                    wordWeight = isActive ? .bold : .medium
                case .karaoke:
                    wordColor = isActive
                        ? Color(red: 0.2, green: 0.95, blue: 1.0)
                        : (isPast ? Color.white.opacity(0.85) : Color.white.opacity(0.45))
                    wordWeight = .bold
                }

                let textChunk = Text(w.word + (index < contextWords.count - 1 ? " " : ""))
                    .font(.system(size: baseSize, weight: wordWeight, design: .rounded))
                    .foregroundColor(wordColor)

                return result + textChunk
            }
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.9), radius: 3, x: 1, y: 1)
            .shadow(color: .black.opacity(0.9), radius: 3, x: -1, y: -1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                viewModel.selectedSubtitleStyle == .minimalDark
                    ? Color.black.opacity(0.75)
                    : Color.black.opacity(0.3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: maxWidth)
        } else {
            // Fallback inicial con gancho editorial
            let hookText = viewModel.selectedClip?.hook ?? ""
            if !hookText.isEmpty {
                Text(hookText)
                    .font(.system(size: viewModel.selectedSubtitleSize.pointSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.9), radius: 3, x: 1, y: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: maxWidth)
            }
        }
    }
}
