import Foundation

// Assert-based self-check: ./OpenCodeUsage --selftest
enum SelfTest {
    static func run() -> Never {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            if !ok {
                failures += 1
                print("FAIL \(name)")
            }
        }

        // $2 in the 5h window, $50 this month out of a $100 limit.
        let five: [[String: Any]] = [
            ["provider": "opencode-go", "model": "deepseek-v4.1-flash", "totalCostMicroCents": "200000000"],
            ["provider": "other", "model": "ignored", "totalCostMicroCents": "999999999"],
        ]
        let week: [[String: Any]] = [
            ["provider": "opencode-go", "model": "deepseek-v4.1-flash", "totalCostMicroCents": "1000000000"],
        ]
        let month: [[String: Any]] = [
            [
                "provider": "opencode-go", "model": "deepseek-v4.1-flash",
                "totalCostMicroCents": "5000000000",
                "totalRequests": "359",
                "totalInputTokens": "2913436",
                "totalOutputTokens": "186447",
                "totalCacheReadTokens": "116727552",
                "totalCacheWrite5mTokens": "1000",
                "totalCacheWrite1hTokens": "2000",
            ],
            [
                "provider": "opencode-go", "model": "glm-5.3",
                "totalCostMicroCents": "1500000000",
                "totalRequests": "10",
                "totalInputTokens": "100",
                "totalOutputTokens": "200",
                "totalCacheReadTokens": "300",
                "totalCacheWrite5mTokens": "0",
                "totalCacheWrite1hTokens": "0",
            ],
        ]
        let today: [[String: Any]] = [
            ["provider": "opencode-go", "model": "deepseek-v4.1-flash", "totalCostMicroCents": "50000000"],
        ]

        let now = Date()
        let since: [Period: Date] = [
            .five: now.addingTimeInterval(-5 * 3600),
            .week: Usage.weekStart(now),
            .month: Usage.monthStart(now),
            .today: Usage.calendar.startOfDay(for: now),
        ]
        let data = Usage.aggregate(
            windows: [.five: five, .week: week, .month: month, .today: today],
            since: since,
            plan: "go"
        )

        check(data.five == 2, "five-hour total")
        check(data.week == 10, "week total")
        check(data.month == 65, "month total")
        check(data.today == 0.5, "today total")
        check(data.models.count == 2, "filters non-go providers")
        check(data.monthRequests == 369, "month requests")
        check(data.input == 2913536, "input tokens")
        check(data.cacheWrite == 3000, "cache write = 5m + 1h")

        // Sorted by month-of-limit: 50/100 = 50%, then 15/15 = 100% would win,
        // so check the 100% model comes first.
        check(data.models.first?.id == "glm-5.3", "sorts by monthly utilization")
        check(data.models.first?.limit == 15, "limit from go table")
        check(data.models.last?.limit == 100, "unknown-model limit")

        let top = Usage.top(data, .five)
        check(top?.model.id == "deepseek-v4.1-flash", "5h top model")
        check(abs((top?.pct ?? 0) - 2 / 20) < 0.0001, "5h cap = 20% of limit")

        check(Usage.percent(0.0723) == "7%", "percent rounding")
        check(Usage.money(144_312_426.0 / 100_000_000.0) == "$1.44", "money 2dp")
        check(Usage.money(1234) == "$1234", "money no dp")
        check(Usage.compact(116_727_552) == "116.7M", "compact millions")
        check(Usage.compact(999) == "999", "compact small")
        check(Usage.offset.count == 6 && Usage.offset.hasPrefix("+") == (TimeZone.current.secondsFromGMT() >= 0), "offset format")
        check(Usage.offset.dropFirst().contains(":"), "offset has minutes")

        let weekStart = Usage.weekStart(now)
        check(Usage.calendar.component(.weekday, from: weekStart) == 2, "week starts Monday")
        check(Usage.calendar.component(.hour, from: weekStart) == 0, "week starts at midnight")
        check(Usage.iso.string(from: weekStart).hasSuffix("Z"), "since is UTC ISO")

        // A plan or model we have no limit for must render as "no limit data"
        // instead of dividing by zero or claiming "unlimited".
        let unknown = Usage.aggregate(
            windows: [.five: [], .week: [], .month: [["provider": "opencode-go", "model": "brand-new", "totalCostMicroCents": "10000000"]], .today: []],
            since: since,
            plan: "go_plus"
        )
        check(unknown.models.first?.limit == nil, "unknown model has no limit")
        check(Usage.cap(unknown.models[0], .month) == nil, "no cap without a limit")
        check(Usage.top(unknown, .month) == nil, "no percentage without a limit")

        print(failures == 0 ? "selftest ok" : "selftest failed: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
