import SwiftUI
import AVKit

public struct ClipCardView: View {
    let clip: ClipDecision
    let videoURL: URL?
    let isActive: Bool
    let viewModel: AppViewModel
    let onEdit: () -> Void
    let onQuickExport: () -> Void

    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = true
    @State private var isMuted: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var totalDuration: Double = 0.0
    @State private var timeObserverToken: Any? = nil

    public init(
        clip: ClipDecision,
        videoURL: URL?,
        isActive: Bool = true,
        viewModel: AppViewModel,
        onEdit: @escaping () -> Void,
        onQuickExport: @escaping () -> Void
    ) {
        self.clip = clip
        self.videoURL = videoURL
        self.isActive = isActive
        self.viewModel = viewModel
        self.onEdit = onEdit
        self.onQuickExport = onQuickExport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Contenedor 9:16 de previsualización con controles integrados
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                    .aspectRatio(9/16, contentMode: .fit)
                    .overlay(
                        Group {
                            if let player = player {
                                SmartFramedPlayerView(
                                    player: player,
                                    mode: .autoFaceTrack,
                                    speakerCenterX: 0.5,
                                    cornerRadius: 22
                                )
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "film.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(.gray)
                                    Text("9:16 Preview")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    )
                    .onTapGesture {
                        togglePlayPause()
                    }

                // Overlay superior: Badge de viralidad y Audio
                VStack {
                    HStack {
                        // Virality Score Badge
                        HStack(spacing: 4) {
                            Text("🔥")
                            Text("\(clip.viralScore)%")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color.red.opacity(0.4), radius: 6, y: 2)

                        Spacer()

                        // Botón de audio (Mute/Unmute)
                        Button(action: {
                            isMuted.toggle()
                            player?.isMuted = isMuted
                            viewModel.triggerHapticFeedback(type: .light)
                        }) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Circle())
                        }
                    }
                    .padding(14)

                    Spacer()

                    // Botón central Play grande si está pausado
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
                        Spacer()
                    }

                    // Controles Inferiores de Transporte (Scrubber, -5s, +5s, time)
                    VStack(spacing: 6) {
                        // Barra Scrubber
                        Slider(
                            value: Binding(
                                get: { currentTime },
                                set: { seek(to: $0) }
                            ),
                            in: 0...max(1.0, totalDuration)
                        )
                        .accentColor(.orange)

                        HStack {
                            Text(formatTime(currentTime))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))

                            Spacer()

                            HStack(spacing: 16) {
                                Button(action: { seek(to: max(0, currentTime - 5)) }) {
                                    Image(systemName: "gobackward.5")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                }

                                Button(action: togglePlayPause) {
                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.orange)
                                }

                                Button(action: { seek(to: min(totalDuration, currentTime + 5)) }) {
                                    Image(systemName: "goforward.5")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                }
                            }

                            Spacer()

                            Text(formatTime(totalDuration))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(10)
                }
            }
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                teardownPlayer()
            }
            .onChange(of: isActive) { _, active in
                if !active {
                    player?.pause()
                    isPlaying = false
                } else {
                    player?.play()
                    isPlaying = true
                }
            }

            // Metadatos del Short
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(clip.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer()
                    Text(formatTime(clip.netDuration))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                if !clip.hook.isEmpty {
                    Text("\"\(clip.hook)\"")
                        .font(.system(size: 13, weight: .medium))
                        .italic()
                        .foregroundColor(.orange.opacity(0.9))
                        .lineLimit(2)
                }

                if let beats = clip.storyBeats, !beats.isEmpty {
                    Text("\(beats.count) tomas narrativas cosidas (Story Beats)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.yellow.opacity(0.9))
                } else {
                    Text("\(clip.cutSegments.count) cortes automáticos de silencio")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 4)

            // Botones de acción
            HStack(spacing: 12) {
                Button(action: onQuickExport) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("Quick Export")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onEdit) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Edit & Polish")
                    }
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.yellow, Color.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func setupPlayer() {
        guard let url = videoURL else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        Task {
            var playerItem: AVPlayerItem? = nil
            var effectiveDuration = max(1.0, clip.netDuration)
            var isComposition = false

            // Intentar construir la composición en memoria con jump cuts
            do {
                let comp = try await viewModel.buildComposition(for: clip, sourceURL: url)
                let compDur = (try? await comp.load(.duration).seconds) ?? 0.0
                if compDur > 0.5 {
                    playerItem = AVPlayerItem(asset: comp)
                    effectiveDuration = compDur
                    isComposition = true
                    print("🎬 [ClipCard] Composición multi-corte creada con éxito (\(String(format: "%.1f", compDur))s)")
                } else {
                    print("⚠️ [ClipCard] Composición devolvió duración 0 o demasiado corta: \(compDur)s")
                }
            } catch {
                print("❌ [ClipCard] Error construyendo composición: \(error). Usando fallback directo.")
            }

            let p: AVPlayer
            if let item = playerItem {
                p = AVPlayer(playerItem: item)
            } else {
                print("⚠️ [ClipCard] Usando reproductor directo de video original para rango \(clip.timeRange.start) - \(clip.timeRange.end)")
                let asset = AVURLAsset(url: url)
                let item = AVPlayerItem(asset: asset)
                p = AVPlayer(playerItem: item)
                let startTime = CMTime(seconds: clip.timeRange.start, preferredTimescale: 600)
                await p.seek(to: startTime)
            }

            p.actionAtItemEnd = .none
            p.volume = 1.0
            p.isMuted = isMuted

            await MainActor.run {
                self.totalDuration = effectiveDuration
                self.player = p
                if self.isActive {
                    p.play()
                    self.isPlaying = true
                } else {
                    p.pause()
                    self.isPlaying = false
                }

                // Observador de tiempo para scrubber
                let interval = CMTime(value: 1, timescale: 10)
                self.timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
                    guard let _ = p else { return }
                    self.currentTime = time.seconds
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
                    if self.isActive { p.play() }
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
        self.currentTime = seconds
    }

    private func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
