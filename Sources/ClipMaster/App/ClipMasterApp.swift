import SwiftUI
import AVFoundation

#if os(iOS)
@main
public struct ClipMasterApp: App {
    public init() {
        // Configurar AVAudioSession para reproducción de video con el silent switch activo
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            print("🔊 AVAudioSession activado en modo .playback (audio activo con silent switch)")
        } catch {
            print("⚠️ Error configurando AVAudioSession: \(error)")
        }
    }

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
#else
public struct ClipMasterApp {
    public init() {}
}
#endif
