import SwiftUI
import AVKit
#if os(iOS)
import UIKit
#endif

public struct ExportSuccessSheet: View {
    let videoURL: URL
    let clip: ClipDecision
    var onDismiss: () -> Void

    @State private var isSavedToPhotos: Bool = false
    @State private var isSaving: Bool = false
    @State private var showSystemShareSheet: Bool = false
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    public init(videoURL: URL, clip: ClipDecision, onDismiss: @escaping () -> Void) {
        self.videoURL = videoURL
        self.clip = clip
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header superior
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("¡CLIP EXPORTADO!")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.orange)
                            .tracking(1.5)

                        Text("Listo para Redes Sociales")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Card de Información del Clip
                        clipSummaryCard()

                        // Botón: Guardar en Fotos
                        saveToPhotosButton()

                        // Sección: Publicación Directa
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PUBLICAR EN REDES")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.gray)
                                .tracking(1)
                                .padding(.leading, 4)

                            // Botón Instagram Reels (Directo con LocalIdentifier)
                            instagramReelsButton()

                            // Botón Instagram Stories
                            instagramStoriesButton()

                            // Botón TikTok
                            tikTokButton()
                        }

                        // Botón Más Opciones (AirDrop, WhatsApp, etc.)
                        Button(action: {
                            showSystemShareSheet = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Otras opciones (AirDrop, WhatsApp, etc.)")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        .sheet(isPresented: $showSystemShareSheet) {
            #if os(iOS)
            ShareSheet(activityItems: [videoURL])
            #endif
        }
        .alert("Información", isPresented: $showAlert) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Componentes de la Vista
    @ViewBuilder
    private func clipSummaryCard() -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: 58, height: 78)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(String(format: "%.1fs", clip.netDuration), systemImage: "clock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)

                    Text("•")
                        .foregroundColor(.gray)

                    Text("1080x1920 (9:16)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(red: 0.1, green: 0.1, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func saveToPhotosButton() -> some View {
        Button(action: {
            Task {
                isSaving = true
                let success = await SocialShareService.shared.saveToPhotoLibrary(videoURL: videoURL)
                isSaving = false
                if success {
                    withAnimation(.spring()) {
                        isSavedToPhotos = true
                    }
                    triggerHaptic(type: .success)
                } else {
                    alertMessage = "No se pudo guardar el video en Fotos. Revisa los permisos en Ajustes."
                    showAlert = true
                }
            }
        }) {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: isSavedToPhotos ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                        .font(.system(size: 18, weight: .bold))
                }

                Text(isSavedToPhotos ? "Guardado en tu Galería" : "Guardar en Galería")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                isSavedToPhotos
                    ? LinearGradient(colors: [Color.green.opacity(0.8), Color.green], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color(red: 0.12, green: 0.72, blue: 0.42), Color(red: 0.05, green: 0.55, blue: 0.32)], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.green.opacity(0.3), radius: 8, y: 3)
        }
        .disabled(isSaving || isSavedToPhotos)
    }

    @ViewBuilder
    private func instagramReelsButton() -> some View {
        Button(action: {
            Task {
                let result = await SocialShareService.shared.shareToInstagramReels(videoURL: videoURL)
                handleShareResult(result, appName: "Instagram Reels")
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: "film.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Instagram Reels")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        Text("REELS / POST")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Text("Abre el creador de Reels con tu video seleccionado")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer()

                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.51, green: 0.14, blue: 0.77),
                        Color(red: 0.88, green: 0.18, blue: 0.42),
                        Color(red: 0.98, green: 0.55, blue: 0.16)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.purple.opacity(0.3), radius: 8, y: 3)
        }
    }

    @ViewBuilder
    private func instagramStoriesButton() -> some View {
        Button(action: {
            Task {
                let result = await SocialShareService.shared.shareToInstagramStories(videoURL: videoURL)
                handleShareResult(result, appName: "Instagram Stories")
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)

                    Image(systemName: "circle.dashed")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Instagram Stories")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Abre Stories con el video listo como sticker de fondo")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func tikTokButton() -> some View {
        VStack(spacing: 8) {
            Button(action: {
                Task {
                    let result = await SocialShareService.shared.shareToTikTok(videoURL: videoURL)
                    handleShareResult(result, appName: "TikTok")
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TikTok (Vía Extensión Oficial)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        Text("Guarda y abre el menú para importar directo a TikTok")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer()

                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.cyan.opacity(0.9))
                }
                .padding(14)
                .background(Color(red: 0.08, green: 0.08, blue: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.6), Color.pink.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                )
            }

            // Acceso rápido alternativo para abrir la app de TikTok directo
            Button(action: {
                #if os(iOS)
                if let url = URL(string: "snssdk1233://") ?? URL(string: "tiktok://") {
                    UIApplication.shared.open(url)
                }
                #endif
            }) {
                HStack(spacing: 4) {
                    Text("¿O prefieres abrir TikTok para pulsar '+'?")
                        .foregroundColor(.gray)
                    Text("Abrir TikTok")
                        .foregroundColor(.cyan)
                        .fontWeight(.bold)
                }
                .font(.system(size: 11))
            }
            .padding(.top, 2)
        }
    }

    private func handleShareResult(_ result: SocialShareResult, appName: String) {
        switch result {
        case .success:
            triggerHaptic(type: .success)
        case .openShareSheet:
            triggerHaptic(type: .success)
            showSystemShareSheet = true
        case .appNotInstalled(let message):
            alertMessage = message
            showAlert = true
            triggerHaptic(type: .warning)
        case .failure(let err):
            alertMessage = err
            showAlert = true
            triggerHaptic(type: .error)
        }
    }

    private enum HapticType {
        case success, warning, error
    }

    private func triggerHaptic(type: HapticType) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        switch type {
        case .success: generator.notificationOccurred(.success)
        case .warning: generator.notificationOccurred(.warning)
        case .error: generator.notificationOccurred(.error)
        }
        #endif
    }
}
