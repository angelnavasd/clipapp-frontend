import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var isShowingSplash: Bool = true

    public init() {}

    public var body: some View {
        ZStack {
            Group {
                switch viewModel.navigationState {
                case .home:
                    HomeView(viewModel: viewModel)
                        .transition(.opacity)

                case .videoConfirmation:
                    VideoConfirmAndTrimView(viewModel: viewModel)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

                case .processing:
                    ProcessingView(viewModel: viewModel)
                        .transition(.opacity)

                case .clipsFeed:
                    ClipsFeedView(viewModel: viewModel)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

                case .editor:
                    ClipEditorView(viewModel: viewModel)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: viewModel.navigationState)

            // Splash Screen con fade-out al inicio
            if isShowingSplash {
                SplashScreenView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isShowingSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
}
