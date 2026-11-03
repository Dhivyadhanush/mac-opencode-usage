import Combine
import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var data: UsageData?
    @Published var error: String?
    @Published var busy = false

    private var timer: Timer?

    var refreshMinutes: Int {
        max(1, UserDefaults.standard.object(forKey: "refreshMinutes") as? Int ?? 10)
    }


    var orgId: String {
        UserDefaults.standard.string(forKey: "orgId") ?? ""
    }

    var plan: String {
        let stored = UserDefaults.standard.string(forKey: "plan") ?? "go"
        return Limits.plans[stored] == nil ? "go" : stored
    }

    var warning: Double {
        Double(UserDefaults.standard.object(forKey: "warning") as? Int ?? 80) / 100
    }

    var critical: Double {
        Double(UserDefaults.standard.object(forKey: "critical") as? Int ?? 95) / 100
    }

    init() {
        schedule()
        Task { await refresh() }
    }

    func schedule() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Double(refreshMinutes) * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        do {
            data = try await Usage.fetch(orgId: orgId, plan: plan)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshIfStale() {
        if let data, Date().timeIntervalSince(data.updatedAt) < 60 { return }
        Task { await refresh() }
    }

    func settingsChanged() {
        schedule()
        Task { await refresh() }
    }
}
