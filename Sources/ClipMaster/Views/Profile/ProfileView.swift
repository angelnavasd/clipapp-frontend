import SwiftUI

public struct ProfileView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    // Mock User Data
    @State private var userName: String = "Angel Navas"
    @State private var userEmail: String = "angelnavasdesign@gmail.com"
    @State private var selectedLanguage: String = "Español"
    @State private var enableHaptics: Bool = true
    @State private var enable4KExport: Bool = true
    @State private var showLogoutAlert: Bool = false
    @State private var showRateAlert: Bool = false

    private let languages = ["Español", "English", "Português"]

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // User Profile Card
                        userHeaderCard()

                        // Subscription Card
                        subscriptionCard()

                        // General Preferences
                        preferencesSection()

                        // Community & Support
                        communitySection()

                        // Logout Section
                        logoutSection()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Mi Perfil")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.orange)
                }
            }
            #endif
        }
        .alert("Cerrar Sesión", isPresented: $showLogoutAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Cerrar Sesión", role: .destructive) {
                viewModel.triggerHapticFeedback(type: .medium)
                dismiss()
            }
        } message: {
            Text("¿Estás seguro de que deseas cerrar tu sesión en ClipMaster?")
        }
        .alert("¡Gracias por tu apoyo!", isPresented: $showRateAlert) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text("Tu valoración nos ayuda a seguir mejorando ClipMaster.")
        }
    }

    // MARK: - Tarjeta de Usuario
    @ViewBuilder
    private func userHeaderCard() -> some View {
        HStack(spacing: 16) {
            // Avatar con iniciales y anillo degradado
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.yellow, .orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 64, height: 64)

                Circle()
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
                    .frame(width: 58, height: 58)

                Text("AN")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(userName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("PRO")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }

                Text(userEmail)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Tarjeta de Suscripción
    @ViewBuilder
    private func subscriptionCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                Text("PLAN PRO ACTIVO")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.yellow)
                    .tracking(1)

                Spacer()

                Text("Renovación: 1 Oct 2026")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
            }

            Text("Acceso ilimitado a Gemini 3.7 Flash, exportación en 1080p a 60fps y tracking facial automático.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(2)

            Button(action: {
                viewModel.triggerHapticFeedback(type: .light)
            }) {
                HStack {
                    Text("Gestionar Suscripción")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13))
                }
                .foregroundColor(.orange)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Sección de Preferencias
    @ViewBuilder
    private func preferencesSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREFERENCIAS")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.gray)
                .tracking(1)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                // Selector de Idioma
                HStack {
                    Label("Idioma", systemImage: "globe")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("Idioma", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(Color.white.opacity(0.06))

                // Vibración Háptica
                Toggle(isOn: $enableHaptics) {
                    Label("Vibración Háptica", systemImage: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .tint(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(Color.white.opacity(0.06))

                // Exportación 4K
                Toggle(isOn: $enable4KExport) {
                    Label("Exportar en Máxima Calidad", systemImage: "sparkles.tv")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .tint(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Comunidad y Ayuda
    @ViewBuilder
    private func communitySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AYUDA Y COMUNIDAD")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.gray)
                .tracking(1)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                Button(action: {
                    showRateAlert = true
                    viewModel.triggerHapticFeedback(type: .light)
                }) {
                    HStack {
                        Label("Calificar ClipMaster", systemImage: "star.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }

                Divider().background(Color.white.opacity(0.06))

                Button(action: {
                    viewModel.triggerHapticFeedback(type: .light)
                }) {
                    HStack {
                        Label("Soporte y Feedback", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }

                Divider().background(Color.white.opacity(0.06))

                Button(action: {
                    viewModel.triggerHapticFeedback(type: .light)
                }) {
                    HStack {
                        Label("Privacidad y Términos", systemImage: "hand.raised.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Cerrar Sesión
    @ViewBuilder
    private func logoutSection() -> some View {
        Button(action: {
            showLogoutAlert = true
        }) {
            HStack {
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Cerrar Sesión")
                Spacer()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.red.opacity(0.9))
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
