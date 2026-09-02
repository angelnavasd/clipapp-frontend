import SwiftUI
import AVKit

public struct VideoCanvasView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isPlaying: Bool
    @State private var player: AVPlayer? = nil
    @State private var timeObserverToken: Any? = nil
    @State private var currentPlaybackTime: Double = 0.0
    @State private var totalDuration: Double = 0.0
    @State private var dragOffset: CGSize = .zero

    public init(viewModel: AppViewModel, isPlaying: Binding<Bool> = .constant(false)) {
        self.viewModel = viewModel
        self._isPlaying = isPlaying
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
                .aspectRatio(9/16, contentMode: .fit)
                .overlay(
                    Group {
                        if let player = player {
                            SmartFramedPlayerView(
                                player: player,
                                mode: viewModel.selectedFramingMode,
                                speakerCenterX: viewModel.detectedSpeakerCenterX,
                                speakerCenterY: viewModel.detectedSpeakerCenterY,
                                cornerRadius: 20
                            )
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "film")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray)
                                Text("Cargando Reproductor...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                )
                .onTapGesture {
                    togglePlayPause()
                }

            // Filtro / LUT preview overlay (simulado mediante mezcla de color y contraste)
            if let lut = viewModel.selectedLutPreset {
                Color(hex: lut.thumbnailColor)
                    .opacity(0.12)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            // Subtítulos Dinámicos Interactivos (Arrastrables verticalmente y sincronizados en vivo)
            GeometryReader { geo in
                let currentY = geo.size.height * viewModel.subtitleVerticalOffset + dragOffset.height

                VStack {
                    subtitlePreviewBadge()
                        .position(x: geo.size.width / 2.0, y: max(60, min(geo.size.height - 80, currentY)))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    let newY = currentY
                                    viewModel.subtitleVerticalOffset = min(max(newY / geo.size.height, 0.2), 0.8)
                                    dragOffset = .zero
                                    viewModel.triggerHapticFeedback(type: .medium)
                                }
                        )
                }
            }

            // Overlay de Zona Segura
            if viewModel.showSafeZoneOverlay {
                SafeZoneOverlayView()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            // Botón central flotante si está pausado
            if !isPlaying {
                Button(action: togglePlayPause) {
                    Circle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .offset(x: 2)
                        )
                }
            }

            // Barra inferior de controles completos (Scrubber, -5s, +5s, time, Safe Zone)
            VStack {
                // Barra superior de estado
                HStack {
                    Text(viewModel.selectedFramingMode.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())

                    Spacer()

                    // Toggle Safe Zone
                    Button(action: {
                        viewModel.showSafeZoneOverlay.toggle()
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        Image(systemName: viewModel.showSafeZoneOverlay ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(viewModel.showSafeZoneOverlay ? .yellow : .white.opacity(0.7))
                            .padding(8)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                }
                .padding(10)

                Spacer()

                // Controles de transporte
                VStack(spacing: 4) {
                    // Scrubber Slider
                    Slider(
                        value: Binding(
                            get: { currentPlaybackTime },
                            set: { seek(to: $0) }
                        ),
                        in: 0...max(1.0, totalDuration)
                    )
                    .accentColor(.orange)

                    HStack {
                        Text(formatTime(currentPlaybackTime))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))

                        Spacer()

                        HStack(spacing: 16) {
                            Button(action: { seek(to: max(0, currentPlaybackTime - 5)) }) {
                                Image(systemName: "gobackward.5")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }

                            Button(action: togglePlayPause) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.orange)
                            }

                            Button(action: { seek(to: min(totalDuration, currentPlaybackTime + 5)) }) {
                                Image(systemName: "goforward.5")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        }

                        Spacer()

                        Text(formatTime(totalDuration))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(10)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
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

            // Intentar construir composición en memoria con jump cuts si tiene storyBeats
            do {
                let comp = try await viewModel.buildComposition(for: clip, sourceURL: url)
                let compDur = (try? await comp.load(.duration).seconds) ?? 0.0
                if compDur > 0.5 {
                    playerItem = AVPlayerItem(asset: comp)
                    effectiveDuration = compDur
                    isComposition = true
                    print("🎬 [Editor] Composición creada con éxito (\(String(format: "%.1f", compDur))s)")
                } else {
                    print("⚠️ [Editor] Composición devolvió duración demasiado corta: \(compDur)s")
                }
            } catch {
                print("❌ [Editor] Error construyendo composición: \(error). Usando fallback directo.")
            }

            let p: AVPlayer
            if let item = playerItem {
                p = AVPlayer(playerItem: item)
            } else {
                print("⚠️ [Editor] Usando reproductor directo de video original")
                let asset = AVURLAsset(url: url)
                let item = AVPlayerItem(asset: asset)
                p = AVPlayer(playerItem: item)
                let startTime = CMTime(seconds: clip.timeRange.start, preferredTimescale: 600)
                await p.seek(to: startTime)
            }

            p.actionAtItemEnd = .none
            p.volume = 1.0
            p.isMuted = false

            await MainActor.run {
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
                        p.seek(to: .zero)
                    } else {
                        let startTime = CMTime(seconds: clip.timeRange.start, preferredTimescale: 600)
                        p.seek(to: startTime)
                    }
                    p.play()
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

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Subtítulos Sincronizados Palabra por Palabra en Tiempo Real
    @ViewBuilder
    private func subtitlePreviewBadge() -> some View {
        let (activeWord, contextWords) = viewModel.activeWords(at: currentPlaybackTime)

        if !contextWords.isEmpty {
            switch viewModel.selectedSubtitleStyle {
            case .hormozi:
                HStack(spacing: 6) {
                    ForEach(contextWords, id: \.id) { w in
                        let isActive = (w.id == activeWord?.id)
                        Text(w.word.uppercased())
                            .font(.system(
                                size: isActive
                                    ? viewModel.selectedSubtitleSize.pointSize * 1.15
                                    : viewModel.selectedSubtitleSize.pointSize,
                                weight: .black,
                                design: .rounded
                            ))
                            .foregroundColor(isActive ? Color(red: 1.0, green: 0.9, blue: 0.0) : .white)
                            .shadow(color: .black, radius: 4, x: 2, y: 2)
                            .shadow(color: .black, radius: 4, x: -2, y: -2)
                            .scaleEffect(isActive ? 1.08 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isActive)
                    }
                }
                .padding(.horizontal, 16)

            case .minimalDark:
                HStack(spacing: 5) {
                    ForEach(contextWords, id: \.id) { w in
                        let isActive = (w.id == activeWord?.id)
                        Text(w.word)
                            .font(.system(size: viewModel.selectedSubtitleSize.pointSize * 0.85, weight: isActive ? .bold : .medium))
                            .foregroundColor(isActive ? Color(red: 0.3, green: 0.8, blue: 1.0) : .white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))

            case .karaoke:
                HStack(spacing: 5) {
                    ForEach(contextWords, id: \.id) { w in
                        let isPast = w.end <= currentPlaybackTime
                        let isActive = (w.id == activeWord?.id)
                        Text(w.word)
                            .font(.system(size: viewModel.selectedSubtitleSize.pointSize * 0.9, weight: .bold))
                            .foregroundColor(
                                isActive ? Color(red: 0.2, green: 0.9, blue: 1.0)
                                : (isPast ? Color(red: 0.2, green: 0.7, blue: 0.9) : .white.opacity(0.6))
                            )
                            .shadow(color: .black, radius: 3)
                    }
                }
                .padding(.horizontal, 16)
            }
        } else {
            // Fallback inicial con el gancho editorial
            let hookText = viewModel.selectedClip?.hook.uppercased() ?? "CLIPMASTER"
            Text(hookText)
                .font(.system(size: viewModel.selectedSubtitleSize.pointSize, weight: .black, design: .rounded))
                .foregroundColor(.yellow)
                .shadow(color: .black, radius: 4, x: 2, y: 2)
                .shadow(color: .black, radius: 4, x: -2, y: -2)
                .padding(.horizontal, 16)
        }
    }
}

// Extensión para convertir colores Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
