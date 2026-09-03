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
    @State private var endObserver: NSObjectProtocol? = nil
    @State private var failureObserver: NSObjectProtocol? = nil
    @State private var errorLogObserver: NSObjectProtocol? = nil
    @State private var sourceSize: CGSize? = nil
    /// Poster del primer beat: la card NUNCA queda negra (player en fondo, aún cargando, etc).
    @State private var poster: CGImage? = nil

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
                            if let player = player, isActive, !viewModel.failedClipIds.contains(clip.id) {
                                framedPlayer(player)
                            } else if let poster = poster {
                                posterView(poster)
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
                    teardownPlayer()
                    isPlaying = false
                } else {
                    setupPlayer()
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

    /// FIX-feed: cada card usa el framing de SU clip (no el global del clip 1)
    /// y sigue a los beats durante la reproducción, igual que el export.
    private func framedPlayer(_ player: AVPlayer) -> SmartFramedPlayerView {
        let c = viewModel.framingCenter(atCompTime: currentTime, for: clip)
        return SmartFramedPlayerView(
            player: player,
            mode: viewModel.framingMode(for: clip),
            speakerCenterX: c.x,
            speakerCenterY: c.y,
            cornerRadius: 22,
            sourceSize: sourceSize,
            speakerFaceWidth: c.faceWidth
        )
    }

    /// Poster con el MISMO crop que el video: si el player no está listo, se ve
    /// el frame correcto en vez de negro.
    private func posterView(_ cg: CGImage) -> some View {
        let c = viewModel.framingCenter(atCompTime: currentTime, for: clip)
        let src = sourceSize ?? CGSize(width: cg.width, height: cg.height)
        return GeometryReader { geo in
            let layout = FaceCropCalculator.previewLayout(
                containerSize: geo.size,
                sourceSize: src,
                center: CGPoint(x: c.x, y: c.y),
                faceWidth: c.faceWidth
            )
            Image(cg, scale: 1.0, label: Text(""))
                .resizable()
                .frame(width: layout.size.width, height: layout.size.height)
                .offset(x: layout.offset.width, y: layout.offset.height)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func posterTime() -> Double {
        if let beats = clip.storyBeats, let first = beats.first {
            return (first.start + first.end) / 2.0
        }
        return (clip.timeRange.start + clip.timeRange.end) / 2.0
    }

    private func setupPlayer() {
        guard let url = videoURL else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        Task {
            let asset = AVURLAsset(url: url)
            // Poster inmediato (barato, 1 frame): adiós cards negras
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 360, height: 640)
            if let cg = try? await gen.image(at: CMTime(seconds: posterTime(), preferredTimescale: 600)).image {
                await MainActor.run { self.poster = cg }
            }

            // Solo la card activa crea AVPlayer: nada de players pausados en negro al fondo
            guard isActive else { return }
            // Tamaño natural para preview idéntico al export
            if let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
               let naturalSize = try? await track.load(.naturalSize) {
                await MainActor.run { self.sourceSize = naturalSize }
            }

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
                    print("🎬 [ClipCard] Composición multi-corte creada (\(String(format: "%.1f", compDur))s)")
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

                self.endObserver = NotificationCenter.default.addObserver(
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

                // DIAGNÓSTICO "reproduce y se queda negro": si el item muere,
                // loguear el error REAL y caer al poster (nunca negro eterno).
                self.failureObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime,
                    object: p.currentItem,
                    queue: .main
                ) { note in
                    let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)
                    print("❌ [ClipCard] ITEM FALLÓ clip=\(clip.id): \(err?.domain ?? "?") \(err?.code ?? -1) \(err?.localizedDescription ?? "sin descripción")")
                    viewModel.notePlaybackFailure(clip.id)
                }
                self.errorLogObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemNewErrorLogEntry,
                    object: p.currentItem,
                    queue: .main
                ) { _ in
                    if let log = p.currentItem?.errorLog(),
                       let ev = log.events.last {
                        print("⚠️ [ClipCard] errorLog clip=\(clip.id): \(ev.errorStatusCode) \(ev.errorComment ?? "")")
                    }
                }
            }
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        if let t = endObserver { NotificationCenter.default.removeObserver(t); endObserver = nil }
        if let t = failureObserver { NotificationCenter.default.removeObserver(t); failureObserver = nil }
        if let t = errorLogObserver { NotificationCenter.default.removeObserver(t); errorLogObserver = nil }
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
