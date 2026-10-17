import Foundation

public struct DiscoveredAgent: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let serviceType: String
    public let kind: AgentConnectionKind
    public let transport: RemoteAgentProtocol
    public var urlString: String {
        let scheme = transport.isWebSocket ? "ws" : "http"
        let address = host.contains(":") ? "[\(host)]" : host
        return "\(scheme)://\(address):\(port)"
    }
}

/// Browses advertised agent services only. A discovered address is never considered authenticated.
@MainActor
public final class AgentLANDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    public static let serviceTypes = ["_opencode._tcp.", "_codex._tcp.", "_acp._tcp.", "_fuzzcode-agent._tcp."]
    private var browsers: [NetServiceBrowser] = []
    private var resolvers: [NetService] = []
    private var agents: [String: DiscoveredAgent] = [:]
    private var completion: CheckedContinuation<[DiscoveredAgent], Never>?
    private var timer: Task<Void, Never>?

    public func browse(timeoutSeconds: TimeInterval = 6) async -> [DiscoveredAgent] {
        if completion != nil { return [] }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion = continuation
                for type in Self.serviceTypes {
                    let browser = NetServiceBrowser()
                    browser.delegate = self
                    browser.schedule(in: .main, forMode: .common)
                    browsers.append(browser)
                    browser.searchForServices(ofType: type, inDomain: "local.")
                }
                timer = Task {
                    do { try await Task.sleep(nanoseconds: UInt64(max(0.1, timeoutSeconds) * 1_000_000_000)); finish() }
                    catch {}
                }
            }
        } onCancel: { Task { @MainActor in self.finish() } }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        resolvers.append(service)
        service.resolve(withTimeout: 4)
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard let rawHost = sender.hostName, sender.port > 0 else { return }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        let key = sender.type + sender.name
        let data = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        func text(_ key: String) -> String? { data[key].flatMap { String(data: $0, encoding: .utf8) } }
        let kind = text("agent").flatMap(AgentConnectionKind.init(rawValue:))
            ?? (sender.type.contains("opencode") ? .opencode : sender.type.contains("codex") ? .codex : .customACP)
        let transport = text("protocol").flatMap(RemoteAgentProtocol.init(rawValue:)) ?? .recommended(for: kind)
        guard kind != .native else { return }
        agents[key] = DiscoveredAgent(id: key, name: sender.name, host: host, port: sender.port,
            serviceType: sender.type, kind: kind, transport: transport)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {}

    private func finish() {
        timer?.cancel(); timer = nil
        browsers.forEach { $0.stop(); $0.delegate = nil }; browsers.removeAll()
        resolvers.forEach { $0.stop(); $0.delegate = nil }; resolvers.removeAll()
        let results = agents.values.sorted { $0.name < $1.name }; agents.removeAll()
        completion?.resume(returning: results); completion = nil
    }
}
