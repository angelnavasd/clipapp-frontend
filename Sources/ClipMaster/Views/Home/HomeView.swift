import SwiftUI
import PhotosUI

public struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedPickerItem: PhotosPickerItem? = nil

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("CLIPMASTER")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(1.5)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                        Text("ON-DEVICE AI")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Error Banner (si ocurre alguno)
                        if let error = viewModel.errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: { viewModel.errorMessage = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(14)
                            .background(Color.red.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                            .padding(.horizontal, 20)
                        }

                        // Hero Card / CTA
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [Color.orange.opacity(0.4), Color.clear],
                                            center: .center,
                                            startRadius: 20,
                                            endRadius: 90
                                        )
                                    )
                                    .frame(width: 140, height: 140)

                                Image(systemName: "video.badge.plus")
                                    .font(.system(size: 48, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }

                            VStack(spacing: 8) {
                                Text("Convierte Videos Largos en Shorts Virales")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)

                                Text("Transcripción con WhisperKit, ganchos con Gemini Flash y reencuadre facial automático.")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(white: 0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }

                            PhotosPicker(
                                selection: $selectedPickerItem,
                                matching: .videos,
                                photoLibrary: .shared()
                            ) {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Seleccionar Video Extenso")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.8, blue: 0.2), Color.orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: Color.orange.opacity(0.3), radius: 10, y: 5)
                            }
                            .padding(.horizontal, 12)
                            .onChange(of: selectedPickerItem) { _, newItem in
                                guard let item = newItem else { return }
                                Task {
                                    if let movie = try? await item.loadTransferable(type: MovieTransferable.self) {
                                        await viewModel.processPickedVideo(url: movie.url)
                                    }
                                }
                            }
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)

                        // Quick Settings Section
                        VStack(alignment: .leading, spacing: 14) {
                            Text("AJUSTES PREVIOS")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray)
                                .tracking(1)

                            VStack(spacing: 14) {
                                HStack {
                                    Label("Duración Objetivo", systemImage: "timer")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Duración", selection: $viewModel.targetDuration) {
                                        Text("Auto (20-40s)").tag("Auto (20-40s)")
                                        Text("< 30s").tag("< 30s")
                                        Text("30-60s").tag("30-60s")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.orange)
                                }

                                Divider().background(Color.white.opacity(0.08))

                                HStack {
                                    Label("Idioma de Audio", systemImage: "waveform")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Idioma", selection: $viewModel.selectedLanguage) {
                                        Text("Español").tag("es")
                                        Text("Inglés").tag("en")
                                        Text("Detección Auto").tag("auto")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.orange)
                                }
                            }
                            .padding(16)
                            .background(Color(red: 0.1, green: 0.1, blue: 0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 20)

                        // Banner de Proyectos Recientes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HISTORIAL DE EDICIÓN")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray)
                                .tracking(1)

                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                                    .frame(width: 80, height: 100)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .foregroundColor(.white.opacity(0.6))
                                    )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Podcast Ep. 42 - Arquitectura Limpia")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    Text("5 clips generados • 1080x1920 (9:16)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)

                                    HStack(spacing: 4) {
                                        Text("🔥 94% Virality Score")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(red: 0.1, green: 0.1, blue: 0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

// Transferable helper for video files from PhotosPicker
public struct MovieTransferable: Transferable {
    public let url: URL

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieTransferable(url: copy)
        }
    }
}
