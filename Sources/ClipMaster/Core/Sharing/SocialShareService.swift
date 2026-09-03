import Foundation
import Photos
import SwiftUI
#if os(iOS)
import UIKit
#endif

public enum SocialShareResult {
    case success
    case openShareSheet
    case appNotInstalled(String)
    case failure(String)
}

public final class SocialShareService {
    public static let shared = SocialShareService()

    private init() {}

    // MARK: - Guardar en Fotos (Camera Roll) y Obtener LocalIdentifier
    public func saveToPhotoLibraryAndGetIdentifier(videoURL: URL) async -> String? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            var placeholder: PHObjectPlaceholder? = nil
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                placeholder = request?.placeholderForCreatedAsset
            }) { success, error in
                if success, let localId = placeholder?.localIdentifier {
                    continuation.resume(returning: localId)
                } else {
                    if let error = error {
                        print("❌ [SocialShare] Error guardando video: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func saveToPhotoLibrary(videoURL: URL) async -> Bool {
        return (await saveToPhotoLibraryAndGetIdentifier(videoURL: videoURL)) != nil
    }

    // MARK: - Compartir en Instagram Reels (Post / Reels Creator)
    @MainActor
    public func shareToInstagramReels(videoURL: URL) async -> SocialShareResult {
        #if os(iOS)
        // 1. Guardar primero en Photos para que Instagram pueda leerlo con su LocalIdentifier
        guard let localId = await saveToPhotoLibraryAndGetIdentifier(videoURL: videoURL) else {
            return .failure("No se pudo guardar el video en Fotos para Instagram Reels.")
        }

        // 2. Esquema de Instagram Library para abrir el creador de Reels/Post con el video
        let encodedId = localId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? localId
        if let libraryURL = URL(string: "instagram://library?LocalIdentifier=\(encodedId)"),
           UIApplication.shared.canOpenURL(libraryURL) {
            _ = await UIApplication.shared.open(libraryURL)
            return .success
        }

        // Fallback a share sheet si el esquema directo no responde
        return .openShareSheet
        #else
        return .failure("Solo soportado en iOS")
        #endif
    }

    // MARK: - Compartir en Instagram Stories (Background Sticker)
    @MainActor
    public func shareToInstagramStories(videoURL: URL) async -> SocialShareResult {
        #if os(iOS)
        guard let url = URL(string: "instagram-stories://share?source_application=com.clipmaster.app") else {
            return .failure("URL inválida de Instagram")
        }

        guard UIApplication.shared.canOpenURL(url) else {
            return .appNotInstalled("Instagram no está instalado en este dispositivo.")
        }

        do {
            let videoData = try Data(contentsOf: videoURL)
            let pasteboardItems: [[String: Any]] = [
                ["com.instagram.sharedSticker.backgroundVideo": videoData]
            ]
            let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
                .expirationDate: Date().addingTimeInterval(300)
            ]

            UIPasteboard.general.setItems(pasteboardItems, options: pasteboardOptions)
            _ = await UIApplication.shared.open(url)
            return .success
        } catch {
            return .failure("Error preparando video para Instagram: \(error.localizedDescription)")
        }
        #else
        return .failure("Solo soportado en iOS")
        #endif
    }

    // MARK: - Compartir en TikTok
    @MainActor
    public func shareToTikTok(videoURL: URL) async -> SocialShareResult {
        #if os(iOS)
        // Guardar primero en la galería para que el usuario o la extensión lo tenga listo
        _ = await saveToPhotoLibrary(videoURL: videoURL)

        // En iOS, TikTok no expone un URL scheme público para inyectar videos en su editor
        // La forma oficial y directa en iOS es usar la extensión de TikTok en el ShareSheet del sistema.
        return .openShareSheet
        #else
        return .failure("Solo soportado en iOS")
        #endif
    }
}
