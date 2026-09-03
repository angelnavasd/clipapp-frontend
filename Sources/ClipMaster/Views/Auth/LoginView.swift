import SwiftUI

public struct LoginView: View {
    @ObservedObject var viewModel: AppViewModel
    var onDismiss: (() -> Void)? = nil

    @State private var emailText: String = ""
    @State private var passwordText: String = ""
    @State private var isSignUpMode: Bool = false
    @State private var isLoading: Bool = false

    public init(viewModel: AppViewModel, onDismiss: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            // Glow ambiental de fondo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(y: -180)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header / Logo
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [.yellow, .orange],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )

                            Image(systemName: "film.stack.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 24)

                        Text("ClipMaster")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(1)

                        Text(isSignUpMode ? "Crea tu cuenta y genera shorts virales" : "Inicia sesión para sincronizar tus proyectos")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Botones de Autenticación Social (OAuth)
                    VStack(spacing: 12) {
                        // Sign in with Apple
                        Button(action: {
                            viewModel.triggerHapticFeedback(type: .medium)
                            onDismiss?()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Continuar con Apple")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        // Sign in with Google
                        Button(action: {
                            viewModel.triggerHapticFeedback(type: .medium)
                            onDismiss?()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Continuar con Google")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 24)

                    // Divisor
                    HStack(spacing: 14) {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                        Text("O con tu correo")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                    }
                    .padding(.horizontal, 24)

                    // Formulario de Email y Contraseña
                    VStack(spacing: 14) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            TextField("Correo electrónico", text: $emailText)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                #endif
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            SecureField("Contraseña", text: $passwordText)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        // Botón Principal
                        Button(action: {
                            viewModel.triggerHapticFeedback(type: .medium)
                            onDismiss?()
                        }) {
                            HStack {
                                Spacer()
                                Text(isSignUpMode ? "Crear Cuenta" : "Iniciar Sesión")
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                Spacer()
                            }
                            .foregroundColor(.black)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(
                                    colors: [Color.yellow, Color.orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)

                    // Toggle entre Iniciar Sesión y Registrarse
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUpMode.toggle()
                        }
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        HStack(spacing: 4) {
                            Text(isSignUpMode ? "¿Ya tienes una cuenta?" : "¿No tienes una cuenta?")
                                .foregroundColor(.gray)
                            Text(isSignUpMode ? "Inicia Sesión" : "Regístrate")
                                .foregroundColor(.orange)
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 13))
                    }

                    // Continuar como Invitado
                    Button(action: {
                        onDismiss?()
                        viewModel.triggerHapticFeedback(type: .light)
                    }) {
                        Text("Continuar como invitado")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 4)

                    // Footer legal
                    Text("Al continuar, aceptas los Términos de Servicio y la Política de Privacidad de ClipMaster.")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 24)
                }
            }
        }
    }
}
