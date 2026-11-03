import AppKit
import SwiftUI

@main
struct OpenCodeUsageApp: App {
    @StateObject private var store = Store()

    init() {
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        if CommandLine.arguments.contains("--dump") { Self.dump() }

        // Headless switch for the login item: ./OpenCodeUsage --loginitem on|off
        if let i = CommandLine.arguments.firstIndex(of: "--loginitem"),
           CommandLine.arguments.count > i + 1 {
            let on = CommandLine.arguments[i + 1] == "on"
            try? LoginItem.set(on)
            print("login item \(LoginItem.enabled ? "on" : "off")")
            exit(0)
        }

        // Launching twice (login item plus a manual open) would show two menu bar
        // items that refresh independently. Only the first instance survives.
        if !InstanceLock.acquire() { exit(0) }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }

    // Verifies the whole fetch path without a GUI: ./OpenCodeUsage --dump
    private static func dump() -> Never {
        Task.detached {
            do {
                let defaults = UserDefaults.standard
                let org = defaults.string(forKey: "orgId") ?? ""
                let data = try await Usage.fetch(orgId: org)
                print(Usage.describe(data))
                exit(0)
            } catch {
                print("error: \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(1)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: Store
    @AppStorage("barFive") private var barFive = true
    @AppStorage("barWeek") private var barWeek = true
    @AppStorage("barMonth") private var barMonth = true

    var body: some View {
        let segments = self.segments
        HStack(spacing: 4) {
            // Same needle-gauge motif as the app icon; custom shapes do not
            // render inside a MenuBarExtra label.
            Image(systemName: segments.risk ? "exclamationmark.triangle.fill" : "gauge.with.needle")
            Text(segments.text)
        }
    }

    // Always prefixed so a single visible number cannot be misread: H = 5-hour,
    // W = week, M = month.
    private var segments: (text: String, risk: Bool) {
        guard let data = store.data else { return ("—", false) }

        var picked: [(String, Double?)] = []
        if barFive { picked.append(("H", Usage.top(data, .five)?.pct)) }
        if barWeek { picked.append(("W", Usage.top(data, .week)?.pct)) }
        if barMonth { picked.append(("M", Usage.top(data, .month)?.pct)) }
        if picked.isEmpty { picked.append(("H", Usage.top(data, .five)?.pct)) }

        let risk = picked.compactMap { $0.1 }.contains { $0 >= store.critical }
        let text = picked
            .map { "\($0.0) \($0.1.map(Usage.percent) ?? "—")" }
            .joined(separator: " ")
        return (text, risk)
    }
}

