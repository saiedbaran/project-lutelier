import Foundation
import CoreImage
import ImageIO

enum DepthEngine: String, CaseIterable, Identifiable {
    case device, patchfusion, depthAnything3 = "depth-anything-3", depthPro = "depth-pro"
    var id: String { rawValue }
    var name: String {
        switch self { case .device: return "On-device V2"; case .patchfusion: return "PatchFusion"; case .depthAnything3: return "Depth Anything 3"; case .depthPro: return "Depth Pro" }
    }
}

struct CompanionCapability: Decodable {
    var id: String
    var configured: Bool
    var detail: String
}

private final class NoDepthRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Only explicit Estimate/Refine actions send a photo or crop to the configured local computer.
final class ResearchDepthClient {
    private let session = URLSession(configuration: .ephemeral, delegate: NoDepthRedirects(), delegateQueue: nil)
    private let context = CIContext()

    private func endpoint(_ address: String, path: String, token: String) throws -> URLRequest {
        guard let base = URL(string: address), let host = base.host?.lowercased(), ["http", "https"].contains(base.scheme ?? ""), base.user == nil, base.password == nil, base.query == nil, base.fragment == nil, token.count >= 24 else {
            throw LutelierError.message("Enter a local companion URL and a token of at least 24 characters.")
        }
        let labels = host.split(separator: ".")
        let parts = labels.compactMap { Int($0) }
        let privateIPv4 = labels.count == 4 && parts.count == 4 && parts.allSatisfy { (0...255).contains($0) } && (parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])))
        guard host == "localhost" || host.hasSuffix(".local") || privateIPv4 else { throw LutelierError.message("Use your computer's private LAN address or .local hostname.") }
        let url = base.appendingPathComponent("v1").appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 660
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LutelierError.message("Companion request failed. Check its token, model setup and availability.") }
        guard data.count <= 32 * 1024 * 1024 else { throw LutelierError.message("Companion depth response exceeds the supported size.") }
        return data
    }

    func capabilities(address: String, token: String) async throws -> [CompanionCapability] {
        struct Reply: Decodable { var engines: [CompanionCapability] }
        var request = try endpoint(address, path: "engines", token: token)
        request.timeoutInterval = 15
        return try JSONDecoder().decode(Reply.self, from: await send(request)).engines
    }

    func estimate(_ image: CIImage, engine: DepthEngine, address: String, token: String) async throws -> CIImage {
        let extent = image.extent
        let scale = min(1, 4096 / max(extent.width, extent.height))
        let input = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let data = context.jpegRepresentation(of: input, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.96]), data.count < 20 * 1024 * 1024 else { throw LutelierError.message("Could not prepare the photograph for the companion.") }
        var request = try endpoint(address, path: "depth", token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["engine": engine.rawValue, "image": data.base64EncodedString()])
        struct Reply: Decodable { var engine: String; var convention: String; var texture: String; var width: Int; var height: Int }
        let reply = try JSONDecoder().decode(Reply.self, from: await send(request))
        guard reply.engine == engine.rawValue, reply.convention == "relative-near-white", reply.width > 0, reply.height > 0, reply.width <= 8192, reply.height <= 8192, reply.width * reply.height <= 24_000_000,
              let texture = Data(base64Encoded: reply.texture), let map = CIImage(data: texture), Int(map.extent.width) == reply.width, Int(map.extent.height) == reply.height else { throw LutelierError.message("The companion returned an invalid depth texture.") }
        return map.transformed(by: CGAffineTransform(scaleX: extent.width / map.extent.width, y: extent.height / map.extent.height)).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
    }
}
