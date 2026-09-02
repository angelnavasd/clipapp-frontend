import Foundation

public enum APIError: Error, LocalizedError {
    case invalidURL
    case networkFailure(String)
    case invalidResponse(statusCode: Int)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL de la API inválida."
        case .networkFailure(let msg):
            return "Fallo de conexión de red: \(msg)"
        case .invalidResponse(let code):
            return "El servidor respondió con código de error HTTP \(code)."
        case .decodingError(let msg):
            return "Fallo al procesar respuesta del servidor: \(msg)"
        }
    }
}

/// Cliente de red para comunicarse con el Gateway de IA (NestJS + Gemini Flash)
public final class ClipsAPIService {
    public static let shared = ClipsAPIService()

    public static var defaultBaseURL: URL {
        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:3000")!
        #else
        // IP de tu Mac en la red Wi-Fi local para conectar desde el iPhone físico
        return URL(string: "http://192.168.1.23:3000")!
        #endif
    }

    public var baseURL: URL

    public init(baseURL: URL = ClipsAPIService.defaultBaseURL) {
        self.baseURL = baseURL
    }

    /// Envía la transcripción local enriquecida al backend y recibe el Edit Decision List (EDL)
    public func analyzeTranscript(payload: TranscriptPayload) async throws -> EDLResponse {
        let endpoint = baseURL.appendingPathComponent("api/v1/clips/analyze-transcript")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120.0

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(payload)
        request.httpBody = bodyData

        print("📡 [ClipsAPI] Enviando POST a \(endpoint) con \(payload.words.count) palabras (\(bodyData.count) bytes)...")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("❌ [ClipsAPI] Fallo de red hacia \(endpoint): \(error.localizedDescription)")
            throw APIError.networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Sin cuerpo"
            print("❌ [ClipsAPI] Servidor respondió con HTTP \(httpResponse.statusCode): \(errorBody)")
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        print("📥 [ClipsAPI] Respuesta exitosa recibida (\(data.count) bytes). Decodificando clips...")
        do {
            let decoder = JSONDecoder()
            let edlResponse = try decoder.decode(EDLResponse.self, from: data)
            print("✅ [ClipsAPI] Decodificados \(edlResponse.clips.count) clips con éxito.")
            for (i, clip) in edlResponse.clips.enumerated() {
                let beatsCount = clip.storyBeats?.count ?? 0
                let cutsCount = clip.cutSegments.count
                let beatsDur = clip.storyBeats?.reduce(0.0) { $0 + $1.duration } ?? 0.0
                print("  📋 Clip \(i+1): \"\(clip.title)\" | range=\(clip.timeRange.start)-\(clip.timeRange.end) | beats=\(beatsCount) (\(String(format: "%.1f", beatsDur))s) | cuts=\(cutsCount) | netDur=\(String(format: "%.1f", clip.netDuration))s")
                clip.storyBeats?.enumerated().forEach { j, beat in
                    print("    🎬 Beat \(j+1) [\(beat.role)]: \(beat.start)-\(beat.end) (\(String(format: "%.1f", beat.duration))s) \"\(beat.text.prefix(50))\"")
                }
            }
            return edlResponse
        } catch {
            let responseStr = String(data: data, encoding: .utf8) ?? ""
            print("❌ [ClipsAPI] Error decodificando EDL: \(error). Respuesta: \(responseStr.prefix(500))")
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Obtiene el catálogo de pistas musicales para Auto-Ducking
    public func fetchMusicCatalog() async throws -> [MusicTrackItem] {
        let endpoint = baseURL.appendingPathComponent("api/v1/assets/music")
        let (data, response) = try await URLSession.shared.data(from: endpoint)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct ResponseWrapper: Codable {
            let status: String
            let data: [MusicTrackItem]
        }

        let wrapper = try JSONDecoder().decode(ResponseWrapper.self, from: data)
        return wrapper.data
    }

    /// Obtiene la lista de presets de filtros / LUTs
    public func fetchLutPresets() async throws -> [LutPresetItem] {
        let endpoint = baseURL.appendingPathComponent("api/v1/assets/luts")
        let (data, response) = try await URLSession.shared.data(from: endpoint)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct ResponseWrapper: Codable {
            let status: String
            let data: [LutPresetItem]
        }

        let wrapper = try JSONDecoder().decode(ResponseWrapper.self, from: data)
        return wrapper.data
    }
}
