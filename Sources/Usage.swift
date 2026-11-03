import Foundation
import SQLite3

// Port of ~/dot-files/cachyos/noctalia/plugins/opencode-usage/lib/usage.luau.
// Difference: credentials are read straight from auth.json instead of running
// `opencode auth export`, so the app needs no shell and no PATH.

enum Period: String, CaseIterable {
    case five, week, month, today
}

struct ModelUsage: Identifiable {
    let id: String
    var five = 0.0
    var week = 0.0
    var month = 0.0
    var today = 0.0
    var requests = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var limit: Double?

    func value(_ period: Period) -> Double {
        switch period {
        case .five: return five
        case .week: return week
        case .month: return month
        case .today: return today
        }
    }
}

struct UsageData {
    var five = 0.0
    var week = 0.0
    var month = 0.0
    var today = 0.0
    var monthRequests = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var models: [ModelUsage] = []
    var plan = "go"
    var updatedAt = Date()
    var fiveSinceAt = Date()
    var weekSinceAt = Date()
    var monthSinceAt = Date()
    var todaySinceAt = Date()
}

enum Limits {
    // Lifted from the Luau plugin. Only `go` is supported; add the other plan
    // tables here if the plan ever changes.
    static let go: [String: Double] = [
        "glm-5.3-flash": 60,
        "glm-5.3": 15,
        "glm-5.2": 60,
        "kimi-k3.1-pro": 15,
        "kimi-k3": 15,
        "kimi-k2.7-code": 60,
        "longcat-2.0": 60,
        "step-5-preview": 15,
        "mimo-v2.6-flash": 60,
        "mimo-v2.6-pro": 15,
        "mimo-v2.5": 60,
        "mimo-v2.5-pro": 15,
        "minimax-m3.1-flash": 20,
        "minimax-m3": 60,
        "muse-spark-1.3-contributor": 60,
        "muse-spark-1.2-contributor": 60,
        "qwen3.8-max": 15,
        "qwen3.8-flash": 30,
        "qwen3.7-plus": 60,
        "deepseek-v4.1-flash": 100,
        "deepseek-v4-pro": 15,
        "hy4-preview": 30,
        "hy3": 60,
        "grok-4.7": 15,
        "gpt-6-luna": 15,
        "gpt-5.6-luna": 15,
        "claude-haiku-5-5": 15,
        "gemini-4-argon": 30,
    ]

    static func value(plan: String, model: String) -> Double? {
        go[model]
    }
}

enum Usage {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    struct Top {
        let model: ModelUsage
        let pct: Double
        let value: Double
        let cap: Double
    }

    static let api = "https://opencode.ai/console/api"

    // MARK: - Windows

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday, matching the Linux widget.
        return calendar
    }

    static func weekStart(_ now: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    }

    static func monthStart(_ now: Date) -> Date {
        calendar.dateInterval(of: .month, for: now)?.start ?? now
    }

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Limits and formatting

    static func cap(_ model: ModelUsage, _ period: Period) -> Double? {
        guard let limit = model.limit, limit > 0 else { return nil }
        switch period {
        case .five: return limit * 0.2
        case .week: return limit * 0.5
        case .month: return limit
        case .today: return nil
        }
    }

    static func top(_ data: UsageData?, _ period: Period) -> Top? {
        guard let data else { return nil }
        var best: Top?
        for model in data.models {
            guard let cap = cap(model, period), cap > 0 else { continue }
            let pct = model.value(period) / cap
            if best == nil || pct > best!.pct {
                best = Top(model: model, pct: pct, value: model.value(period), cap: cap)
            }
        }
        return best
    }

    static func money(_ value: Double) -> String {
        if value >= 100 { return String(format: "$%.0f", value) }
        if value >= 10 { return String(format: "$%.1f", value) }
        if value >= 0.01 { return String(format: "$%.2f", value) }
        if value > 0 { return String(format: "$%.3f", value) }
        return "$0.00"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    static func compact(_ value: Int) -> String {
        let n = Double(value)
        if n >= 1_000_000_000 { return String(format: "%.1fB", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", n / 1_000) }
        return String(Int(n))
    }

    // MARK: - HTTP

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func request(_ url: URL, key: String, org: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if !org.isEmpty { request.setValue(org, forHTTPHeaderField: "x-org-id") }

        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(decoding: data.prefix(400), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if status == 401 || status == 403 {
                throw Failure("The OpenCode Go key was rejected (HTTP \(status)). It is probably expired — run `opencode auth login` to refresh it. \(body.prefix(120))")
            }
            throw Failure("HTTP \(status) from the usage API: \(body.prefix(180))")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("Could not parse the usage API response.")
        }
        return object
    }

    static func credential() throws -> String {
        if let key = try? databaseKey() { return key }
        if let key = try? legacyFileKey() { return key }
        throw Failure("No OpenCode Go credential found. Run `opencode auth login`.")
    }

    // opencode v2 keeps credentials in opencode.db; auth.json is only left over
    // from v1 and can hold an expired key, so the DB is the primary source.
    static func databaseKey() throws -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
        var database: OpaquePointer?
        guard sqlite3_open_v2(path.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            throw Failure("Could not open the OpenCode credential database.")
        }
        defer { sqlite3_close(database) }

        let sql = """
            select value from credential
            where integration_id = 'opencode-go' and active = 1
            order by time_updated desc limit 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw Failure("Could not read the OpenCode credential database.")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0),
              let data = String(cString: text).data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("No OpenCode Go credential found. Run `opencode auth login`.")
        }
        if let key = entry["key"] as? String, !key.isEmpty { return key }
        if let key = entry["access"] as? String, !key.isEmpty { return key }
        throw Failure("No OpenCode Go credential found. Run `opencode auth login`.")
    }

    static func legacyFileKey() throws -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("Could not read OpenCode credentials. Run `opencode auth login`.")
        }
        let entry = root["opencode-go"] as? [String: Any] ?? [:]
        if let key = entry["key"] as? String, !key.isEmpty { return key }
        if let key = entry["access"] as? String, !key.isEmpty { return key }
        throw Failure("No OpenCode Go credential found. Run `opencode auth login`.")
    }

    static func models(since: Date, key: String, org: String) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var page = 1
        while true {
            var components = URLComponents(string: api + "/usage/models")!
            components.queryItems = [
                URLQueryItem(name: "since", value: iso.string(from: since)),
                URLQueryItem(name: "pageSize", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ]

            let body = try await request(components.url!, key: key, org: org)
            items += body["items"] as? [[String: Any]] ?? []

            let info = body["pageInfo"] as? [String: Any] ?? [:]
            let next = Int(number(info["page"]) ?? Double(page))
            let count = Int(number(info["pageCount"]) ?? 1)
            guard next < count else { return items }
            page = next + 1
        }
    }

    // MARK: - Aggregation

    static func aggregate(
        windows: [Period: [[String: Any]]],
        since: [Period: Date],
        plan: String
    ) -> UsageData {
        var data = UsageData(plan: plan)
        data.fiveSinceAt = since[.five] ?? Date()
        data.weekSinceAt = since[.week] ?? Date()
        data.monthSinceAt = since[.month] ?? Date()
        data.todaySinceAt = since[.today] ?? Date()

        var byId: [String: ModelUsage] = [:]
        var order: [String] = []

        for period in Period.allCases {
            for item in windows[period] ?? [] {
                guard item["provider"] as? String == "opencode-go" else { continue }
                let id = item["model"] as? String ?? "(unknown)"
                var model = byId[id] ?? ModelUsage(id: id, limit: Limits.value(plan: plan, model: id))
                if byId[id] == nil { order.append(id) }

                let cost = (number(item["totalCostMicroCents"]) ?? 0) / 100_000_000

                switch period {
                case .five:
                    model.five = cost
                    data.five += cost
                case .week:
                    model.week = cost
                    data.week += cost
                case .today:
                    model.today = cost
                    data.today += cost
                case .month:
                    model.month = cost
                    data.month += cost
                    model.requests = Int(number(item["totalRequests"]) ?? 0)
                    model.input = Int(number(item["totalInputTokens"]) ?? 0)
                    model.output = Int(number(item["totalOutputTokens"]) ?? 0)
                    model.cacheRead = Int(number(item["totalCacheReadTokens"]) ?? 0)
                    model.cacheWrite = Int(number(item["totalCacheWrite5mTokens"]) ?? 0)
                        + Int(number(item["totalCacheWrite1hTokens"]) ?? 0)

                    data.monthRequests += model.requests
                    data.input += model.input
                    data.output += model.output
                    data.cacheRead += model.cacheRead
                    data.cacheWrite += model.cacheWrite
                }
                byId[id] = model
            }
        }

        data.models = order.compactMap { byId[$0] }.sorted { a, b in
            let aUse = a.limit.map { $0 > 0 ? a.month / $0 : -1 } ?? -1
            let bUse = b.limit.map { $0 > 0 ? b.month / $0 : -1 } ?? -1
            return aUse == bUse ? a.month > b.month : aUse > bUse
        }
        data.updatedAt = Date()
        return data
    }

    static func fetch(orgId: String, plan: String = "go") async throws -> UsageData {
        let key = try credential()
        // The key already implies its workspace; x-org-id is only needed when a
        // key can reach several, so an empty value simply omits the header.
        let org = orgId

        let now = Date()
        let since: [Period: Date] = [
            .five: now.addingTimeInterval(-5 * 3600),
            .week: weekStart(now),
            .month: monthStart(now),
            .today: calendar.startOfDay(for: now),
        ]

        var windows: [Period: [[String: Any]]] = [:]
        try await withThrowingTaskGroup(of: (Period, [[String: Any]]).self) { group in
            for period in Period.allCases {
                let at = since[period]!
                group.addTask {
                    (period, try await models(since: at, key: key, org: org))
                }
            }
            for try await (period, items) in group {
                windows[period] = items
            }
        }
        return aggregate(windows: windows, since: since, plan: plan)
    }

    // MARK: - Debug dump

    static func describe(_ data: UsageData) -> String {
        var lines = ["plan \(data.plan) · updated \(data.updatedAt)"]
        for period in [Period.five, .week, .month] {
            if let top = top(data, period) {
                lines.append("\(period.rawValue): \(percent(top.pct)) · \(top.model.id) · \(money(top.value)) of \(money(top.cap))")
            } else {
                lines.append("\(period.rawValue): —")
            }
        }
        lines.append("today \(money(data.today))")
        for model in data.models {
            lines.append(
                "  \(model.id) limit \(model.limit.map(money) ?? "unlimited") "
                    + "5h \(money(model.five)) week \(money(model.week)) month \(money(model.month))"
            )
        }
        return lines.joined(separator: "\n")
    }
}
