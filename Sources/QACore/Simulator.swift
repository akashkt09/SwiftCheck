import Foundation

public struct SimulatorDevice {
    public let name: String
    public let udid: String
    public let runtimeIdentifier: String
    public let isBooted: Bool
}

// Why: parse `simctl list devices available -j` instead of hardcoding a device name — availability varies by Xcode/runtime install.
public func listAvailableSimulators() -> [SimulatorDevice] {
    let result = shell("xcrun", ["simctl", "list", "devices", "available", "-j"])
    guard result.exitCode == 0,
          let data = result.output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let devicesByRuntime = json["devices"] as? [String: [[String: Any]]] else {
        return []
    }

    var devices: [SimulatorDevice] = []
    for (runtime, entries) in devicesByRuntime {
        for entry in entries {
            guard let name = entry["name"] as? String, let udid = entry["udid"] as? String else { continue }
            devices.append(SimulatorDevice(
                name: name,
                udid: udid,
                runtimeIdentifier: runtime,
                isBooted: (entry["state"] as? String) == "Booted"
            ))
        }
    }
    return devices
}

// Why: prefer an already-booted simulator (skips the boot wait); otherwise fall back to an iPhone on the newest installed iOS runtime.
public func selectSimulator(from devices: [SimulatorDevice]) -> SimulatorDevice? {
    if let booted = devices.first(where: { $0.isBooted && $0.runtimeIdentifier.contains(".SimRuntime.iOS-") }) {
        return booted
    }

    let iOSDevices = devices.filter { $0.runtimeIdentifier.contains(".SimRuntime.iOS-") }
    guard let latestRuntime = iOSDevices.map({ $0.runtimeIdentifier }).max(by: { isVersion($0, lessThan: $1) }) else {
        return nil
    }

    let onLatestRuntime = iOSDevices.filter { $0.runtimeIdentifier == latestRuntime }
    return onLatestRuntime.first(where: { $0.name.hasPrefix("iPhone") }) ?? onLatestRuntime.first
}

// Why: runtime identifiers sort lexicographically wrong ("iOS-9" > "iOS-18" as strings), so compare the numeric components instead.
private func runtimeVersion(_ identifier: String) -> [Int] {
    let versionPart = identifier.components(separatedBy: ".SimRuntime.iOS-").last ?? ""
    return versionPart.split(separator: "-").compactMap { Int($0) }
}

private func isVersion(_ lhs: String, lessThan rhs: String) -> Bool {
    let (left, right) = (runtimeVersion(lhs), runtimeVersion(rhs))
    for (l, r) in zip(left, right) where l != r {
        return l < r
    }
    return left.count < right.count
}
