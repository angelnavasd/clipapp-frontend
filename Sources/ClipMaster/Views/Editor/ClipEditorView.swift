import SwiftUI

public struct ClipEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isPlaying: Bool = true
    @State private var currentPlaybackTime: Double = 0.0
    @State private var totalDuration: Double = 0.0
    @State private var seekActionTime: Double? = nil
    @State private var showExportSheet: Bool = false
    @State private var showTranscriptDrawer: Bool = false
    @State private var activePanel: EditorSubPanel? = nil

    enum EditorSubPanel {
        case captions
        case framing
        case filters
    }

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                // Top Bar Limpia
                topNavigationBar()

                // Contenedor Central con Video y Controles
                GeometryReader { geo in
                    let videoHeight = min(370, geo.size.height * 0.54)

                    VStack(spacing: 8) {
                        // Video Canvas 9:16 sin elementos que lo tapen
                        VideoCanvasView(
                            viewModel: viewModel,
                            isPlaying: $isPlaying,
                            currentPlaybackTime: $currentPlaybackTime,
                            totalDuration: $totalDuration,
                            seekActionTime: $seekActionTime
                        )
                        .frame(height: videoHeight)

                        // Barra de Transporte Completa y Espaciosa
                        transportControlBar()
                            .padding(.horizontal, 16)

                        // Botonera de Herramientas Des-saturada
                        actionPillBar()
                            .padding(.horizontal, 16)

                        // Panel Contextual de Herramientas
                        panelContent()
                            .padding(.horizontal, 16)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showTranscriptDrawer) {
            TranscriptDrawerSheet(viewModel: viewModel) { targetTime in
                seekActionTime = targetTime
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = viewModel.exportedVideoURL, let clip = viewModel.selectedClip {
                ExportSuccessSheet(videoURL: url, clip: clip) {
                    showExportSheet = false
                }
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
        .overlay(
            Group {
                if viewModel.isExporting {
                    exportingOverlay()
                }
            }
        )
    }

    // MARK: - Barra de Navegación Superior
    @ViewBuilder
    private func topNavigationBar() -> some View {
        HStack {
            Button(action: {
                viewModel.navigationState = .clipsFeed
                viewModel.triggerHapticFeedback(type: .light)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Clips")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.orange)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("9:16 • 1080x1920")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            Spacer()

            Button(action: {
                Task {
                    await viewModel.exportCurrentClip()
                    if viewModel.exportedVideoURL != nil {
                        showExportSheet = true
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Export")
                }
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    // MARK: - Barra de Transporte (Scrubber y Playback)
    @ViewBuilder
    private func transportControlBar() -> some View {
        VStack(spacing: 4) {
            // Scrubber Slider a Pantalla Completa
            Slider(
                value: Binding(
                    get: { currentPlaybackTime },
                    set: { seekActionTime = $0 }
                ),
                in: 0...max(1.0, totalDuration)
            )
            .tint(.orange)

            HStack {
                Text(formatTime(currentPlaybackTime))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                HStack(spacing: 24) {
                    // -5s
                    Button(action: {
                        seekActionTime = max(0, currentPlaybackTime - 5)
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    // Play / Pause
                    Button(action: {
                        isPlaying.toggle()
                        viewModel.triggerHapticFeedback(type: .medium)
                    }) {
                        Circle()
                            .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .black))
                                    .foregroundColor(.black)
                                    .offset(x: isPlaying ? 0 : 1)
                            )
                    }

                    // +5s
                    Button(action: {
                        seekActionTime = min(totalDuration, currentPlaybackTime + 5)
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                Spacer()

                Text(formatTime(totalDuration))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.1, green: 0.1, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Barra de Botones Principales (Pill Bar)
    @ViewBuilder
    private func actionPillBar() -> some View {
        HStack(spacing: 8) {
            // Botón Subtítulos (Abre el Drawer para editar palabras)
            Button(action: {
                showTranscriptDrawer = true
                viewModel.triggerHapticFeedback(type: .light)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 13))
                    Text("Guion")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 1))
            }

            // Botón Estilo Subtítulos
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activePanel = (activePanel == .captions) ? nil : .captions
                }
                viewModel.triggerHapticFeedback(type: .light)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "textformat")
                        .font(.system(size: 13))
                    Text("Estilo")
                        .font(.system(size: 12, weight: activePanel == .captions ? .bold : .medium))
                }
                .foregroundColor(activePanel == .captions ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(activePanel == .captions ? Color.white : Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            // Botón Encuadre
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activePanel = (activePanel == .framing) ? nil : .framing
                }
                viewModel.triggerHapticFeedback(type: .light)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 13))
                    Text("Encuadre")
                        .font(.system(size: 12, weight: activePanel == .framing ? .bold : .medium))
                }
                .foregroundColor(activePanel == .framing ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(activePanel == .framing ? Color.white : Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            // Botón Filtros
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activePanel = (activePanel == .filters) ? nil : .filters
                }
                viewModel.triggerHapticFeedback(type: .light)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 13))
                    Text("Filtros")
                        .font(.system(size: 12, weight: activePanel == .filters ? .bold : .medium))
                }
                .foregroundColor(activePanel == .filters ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(activePanel == .filters ? Color.white : Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Contenido Dinámico del Panel Seleccionado
    @ViewBuilder
    private func panelContent() -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let panel = activePanel {
                switch panel {
                case .captions:
                    CaptionsPanelView(viewModel: viewModel)
                case .framing:
                    FramingPanelView(viewModel: viewModel)
                case .filters:
                    ColorFilterPanelView(viewModel: viewModel)
                }
            } else {
                // Card de Acceso Rápido al Guion si no hay panel abierto
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ESTILO ACTIVO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text("\(viewModel.selectedSubtitleStyle.rawValue) • Tamaño \(viewModel.selectedSubtitleSize.rawValue)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Button(action: {
                        showTranscriptDrawer = true
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        HStack(spacing: 4) {
                            Text("Editar Guion")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Overlay de Exportación
    @ViewBuilder
    private func exportingOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .scaleEffect(2.0)

                Text("Renderizando Composición...")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)

                Text("Quemando jump cuts, subtítulos sincronizados y audio.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Text("\(Int(viewModel.exportProgress * 100))%")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .padding(28)
            .background(Color(red: 0.1, green: 0.1, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#if os(iOS)
import UIKit

public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]

    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

