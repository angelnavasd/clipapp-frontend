import SwiftUI

public struct ClipEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isPlaying: Bool = true
    @State private var showExportSheet: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Top Bar
                HStack {
                    Button(action: {
                        viewModel.navigationState = .clipsFeed
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Clips")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.orange)
                    }

                    Spacer()

                    // Indicador de Resolución
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("1080x1920 • 9:16")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())

                    Spacer()

                    // Botón Primario de Exportación
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
                        .padding(.vertical, 8)
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
                .padding(.top, 8)

                // Canvas Central 9:16
                VideoCanvasView(viewModel: viewModel, isPlaying: $isPlaying)
                    .frame(maxHeight: 330)
                    .padding(.horizontal, 24)

                // Tab Bar Inferior para seleccionar panel activo
                HStack(spacing: 6) {
                    editorTabButton(title: "Trim & Text", icon: "scissors", index: 0)
                    editorTabButton(title: "Framing", icon: "person.crop.rectangle", index: 1)
                    editorTabButton(title: "Captions", icon: "captions.bubble", index: 2)
                    editorTabButton(title: "Audio & Vibe", icon: "waveform", index: 3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                // Panel Contextual Activo
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch viewModel.activeEditorTab {
                        case 0:
                            TextTimelineEditorView(viewModel: viewModel)
                        case 1:
                            FramingPanelView(viewModel: viewModel)
                        case 2:
                            CaptionsPanelView(viewModel: viewModel)
                        case 3:
                            AudioVibePanelView(viewModel: viewModel)
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .overlay(
            Group {
                if viewModel.isExporting {
                    ZStack {
                        Color.black.opacity(0.85).ignoresSafeArea()
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(2.2)

                            Text("Renderizando Composición On-Device...")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)

                            Text("Aplicando cortes, auto-ducking y subtítulos dinámicos.")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)

                            Text("\(Int(viewModel.exportProgress * 100))%")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(32)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
        )
        .sheet(isPresented: $showExportSheet) {
            if let url = viewModel.exportedVideoURL {
                #if os(iOS)
                ShareSheet(activityItems: [url])
                #else
                VStack(spacing: 16) {
                    Text("¡Video Exportado con Éxito!")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(24)
                #endif
            }
        }
    }

    private func editorTabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: {
            viewModel.activeEditorTab = index
            viewModel.triggerHapticFeedback(type: .light)
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(viewModel.activeEditorTab == index ? .orange : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                viewModel.activeEditorTab == index
                    ? Color.orange.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

#if canImport(UIKit)
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
