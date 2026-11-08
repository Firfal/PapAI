import Foundation

/// Client WebSocket vers le serveur. Envoie `hello` à chaque connexion et se
/// reconnecte toutes les 3 s.
@MainActor
final class BridgeClient {
    var onMessage: (([String: Any]) -> Void)?
    var onConnection: ((Bool) -> Void)?
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private let session = URLSession(configuration: .default)

    func start(url: URL) {
        stop()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runOnce(url: url)
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onConnection?(false)
    }

    private func runOnce(url: URL) async {
        let t = session.webSocketTask(with: url)
        t.maximumMessageSize = 16 * 1024 * 1024
        task = t
        t.resume()
        do {
            let hello: [String: Any] = [
                "type": "hello",
                "os": "macos",
                "protection": GuardSignals.enabled,
                "web_agent_available": WebAgentHost.isInstalled && WebAgentHost.browserExecutable() != nil
            ]
            try await t.send(.string(Self.json(hello)))
        } catch {
            onConnection?(false)
            return
        }
        onConnection?(true)
        while !Task.isCancelled {
            do {
                let msg = try await t.receive()
                var text: String?
                switch msg {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8)
                @unknown default: break
                }
                if let text, let data = text.data(using: .utf8),
                   let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    onMessage?(obj)
                }
            } catch {
                break
            }
        }
        onConnection?(false)
    }

    func send(_ payload: [String: Any]) {
        guard let t = task else { return }
        let text = Self.json(payload)
        Task { try? await t.send(.string(text)) }
    }

    private static func json(_ d: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
