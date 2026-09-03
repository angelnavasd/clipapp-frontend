import SwiftUI
import AVKit

public struct VideoConfirmAndTrimView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var timeObserverToken: Any? = nil

    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 0.0
    @State private var totalDuration: Double = 0.0
    @State private var isLoadingDuration: Bool = true

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                // Barra Superior
                HStack {
                    Button(action: {
                        viewModel.triggerHapticFeedback(type: .light)
                        viewModel.navigationState = .home
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Cambiar Video")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.orange)
                    }

                    Spacer()

                    Text("CONFIRMAR VIDEO")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                        .tracking(1)

                    Spacer()

                    // Balance visual
                    Text("Cambiar")
                        .font(.system(size: 15))
                        .opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)

                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(3)
                        Spacer()
                        Button(action: { viewModel.errorMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        // Reproductor 16:9 con Controles Completos
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.black)
                                    .aspectRatio(16/9, contentMode: .fit)

                                if let player = player {
                                    VideoPlayer(player: player)
                                        .disabled(true)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                }

                                // Botón flotante central si está pausado
                                if !isPlaying {
                                    Button(action: togglePlayPause) {
                                        Circle()
                                            .fill(Color.black.opacity(0.65))
                                            .frame(width: 56, height: 56)
                                            .overlay(
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 22))
                                                    .foregroundColor(.white)
                                                    .offset(x: 2)
                                            )
                                    }
                                }
                            }
                            .onTapGesture {
                                togglePlayPause()
                            }

                            // Barra de progreso y Controles de Reproducción
                            VStack(spacing: 8) {
                                // Scrubber Slider
                                Slider(
                                    value: Binding(
                                        get: { currentTime },
                                        set: { seek(to: $0) }
                                    ),
                                    in: 0...max(1.0, totalDuration)
                                )
                                .accentColor(.orange)

                                // Tiempos y Botones
                                HStack {
                                    Text(formatTime(currentTime))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))

                                    Spacer()

                                    // Controles de transporte
                                    HStack(spacing: 20) {
                                        Button(action: { seek(to: max(0, currentTime - 5)) }) {
                                            Image(systemName: "gobackward.5")
                                                .font(.system(size: 18))
                                                .foregroundColor(.white)
                                        }

                                        Button(action: togglePlayPause) {
                                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(.orange)
                                        }

                                        Button(action: { seek(to: min(totalDuration, currentTime + 5)) }) {
                                            Image(systemName: "goforward.5")
                                                .font(.system(size: 18))
                                                .foregroundColor(.white)
                                        }
                                    }

                                    Spacer()

                                    Text(formatTime(totalDuration))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 18)

                        // Selector de Rango de Interés (Trimmer)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "slider.horizontal.2.square")
                                    .foregroundColor(.yellow)
                                Text("RANGO DE INTERÉS (OPCIONAL)")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.white)
                                    .tracking(1)
                                Spacer()
                            }

                            Text("¿Quieres procesar solo un fragmento del video? Ajusta el inicio y fin para acelerar el análisis y concentrar los clips en esa sección.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .lineSpacing(3)

                            // Manijas de recorte
                            if isLoadingDuration && totalDuration <= 0 {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                    Text("Preparando línea de tiempo...")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                VStack(spacing: 12) {
                                    // Control de Inicio
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Punto de Inicio:")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.gray)
                                            Spacer()
                                            Text(formatTime(trimStart))
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundColor(.yellow)
                                        }
                                        Slider(
                                            value: $trimStart,
                                            in: 0...max(0, trimEnd - 15),
                                            onEditingChanged: { editing in
                                                if !editing { seek(to: trimStart) }
                                            }
                                        )
                                        .accentColor(.yellow)
                                    }

                                    // Control de Fin
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Punto de Fin:")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.gray)
                                            Spacer()
                                            Text(formatTime(trimEnd))
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundColor(.orange)
                                        }
                                        Slider(
                                            value: $trimEnd,
                                            in: min(totalDuration, trimStart + 15)...max(15, totalDuration),
                                            onEditingChanged: { editing in
                                                if !editing { seek(to: trimEnd - 2) }
                                            }
                                        )
                                        .accentColor(.orange)
                                    }
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }

                            // Resumen del rango seleccionado
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tiempo a procesar:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                    Text(formatTime(max(0, trimEnd - trimStart)))
                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                }

                                Spacer()

                                Button(action: resetToFullVideo) {
                                    Text("Todo el Video")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.orange.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(16)
                        .background(Color(red: 0.08, green: 0.08, blue: 0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 18)

                        // Botón de Confirmación Principal
                        Button(action: confirmAndStartProcessing) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Generar Shorts Virales (\(formatTime(max(0, trimEnd - trimStart))))")
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                LinearGradient(
                                    colors: [Color.yellow, Color.orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color.orange.opacity(0.4), radius: 12, y: 4)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
    }

    // MARK: - Métodos de Reproductor y Control
    private func setupPlayer() {
        guard let url = viewModel.localVideoURL else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        // 1. Si viewModel ya tiene la duración precargada, usarla de inmediato (sin delay ni freeze)
        if viewModel.videoDuration > 0 {
            self.totalDuration = viewModel.videoDuration
            self.trimStart = 0.0
            self.trimEnd = viewModel.videoDuration
            self.isLoadingDuration = false
        }

        let p = AVPlayer(url: url)
        p.volume = 1.0
        p.isMuted = false

        let asset = AVAsset(url: url)
        Task {
            if let dur = try? await asset.load(.duration).seconds, dur > 0 {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.totalDuration = dur
                        if self.trimEnd <= 0 || self.trimEnd > dur {
                            self.trimEnd = dur
                        }
                        self.isLoadingDuration = false
                    }
                }
            }
        }

        let interval = CMTime(value: 1, timescale: 10)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard let _ = p else { return }
            self.currentTime = time.seconds

            // Si el reproductor pasa del punto de fin recortado, hacer bucle al punto de inicio
            if self.trimEnd > self.trimStart && time.seconds >= self.trimEnd {
                self.seek(to: self.trimStart)
            }
        }

        self.player = p
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
            // Si está fuera del rango, saltar al inicio
            if currentTime < trimStart || currentTime >= trimEnd {
                seek(to: trimStart)
            }
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

    private func resetToFullVideo() {
        viewModel.triggerHapticFeedback(type: .medium)
        self.trimStart = 0.0
        self.trimEnd = totalDuration
        seek(to: 0.0)
    }

    private func confirmAndStartProcessing() {
        viewModel.triggerHapticFeedback(type: .success)
        teardownPlayer()

        let isTrimmed = (trimStart > 0.5 || trimEnd < (totalDuration - 0.5))
        let timeRange: TimeRange? = isTrimmed ? TimeRange(start: trimStart, end: trimEnd) : nil

        Task {
            await viewModel.startPipeline(forTrimmedRange: timeRange)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
