/// A normal reconnect adopts the existing authorized transport. Only the user's
/// explicit reset policy permits killing ADB, preserving its known port to retry.
nonisolated struct WirelessReconnectPlan {
    let reusePort: UInt16?
    let resetServer: Bool
    let candidatePorts: [String]

    init(livePort: UInt16?, reportedPorts: [String], resetServer: Bool) {
        self.resetServer = resetServer
        reusePort = resetServer ? nil : livePort
        if resetServer, let livePort {
            candidatePorts = [String(livePort)] + reportedPorts.filter { $0 != String(livePort) }
        } else {
            candidatePorts = reportedPorts
        }
    }
}
