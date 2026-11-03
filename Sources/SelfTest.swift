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
            since: since
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

        // The console meter is authoritative when opencode has a linked
        // workspace: parse percents and the reset instant, ignore everything else.
        let meterJSON = Data("""
        {"data":{"go":{"rolling":{"percent":37,"limited":false,"resetsAt":1762340000000},
        "weekly":{"percent":63.5,"limited":false},
        "monthly":{"percent":100,"limited":true,"resetsAt":1762400000000}},"budgets":[]}}
        """.utf8)
        let meters = Usage.meters(from: meterJSON)
        check(meters?.five.percent == 37, "meter rolling percent")
        check(meters?.week.percent == 63.5, "meter weekly percent")
        check(meters?.five.resetsAt == Date(timeIntervalSince1970: 1_762_340_000), "meter resetsAt ms")
        check(meters?.week.resetsAt == nil, "missing resetsAt is nil")
        check(meters?.meter(.today) == nil, "today has no meter")

        var metered = Usage.aggregate(
            windows: [.five: five, .week: week, .month: month, .today: []],
            since: since
        )
        metered.meters = meters
        check(abs((Usage.top(metered, .five)?.pct ?? 0) - 0.37) < 0.0001, "meter percent wins over spend")
        check(abs((Usage.top(data, .five)?.pct ?? 0) - 0.1) < 0.0001, "no meter falls back to spend")
        check(Usage.meters(from: Data("{\"data\":null}".utf8)) == nil, "null data is no meter")
        check(Usage.meters(from: Data("{}".utf8)) == nil, "missing go is no meter")

        let weekStart = Usage.weekStart(now)
        check(Usage.calendar.component(.weekday, from: weekStart) == 2, "week starts Monday")
        check(Usage.calendar.component(.hour, from: weekStart) == 0, "week starts at midnight")
        check(Usage.iso.string(from: weekStart).hasSuffix("Z"), "since is UTC ISO")

        // A model we have no limit for must render as "no limit data" instead
        // of dividing by zero or claiming "unlimited".
        let unknown = Usage.aggregate(
            windows: [.five: [], .week: [], .month: [["provider": "opencode-go", "model": "brand-new", "totalCostMicroCents": "10000000"]], .today: []],
            since: since
        )
        check(unknown.models.first?.limit == nil, "unknown model has no limit")
        check(Usage.cap(unknown.models[0], .month) == nil, "no cap without a limit")
        check(Usage.top(unknown, .month) == nil, "no percentage without a limit")

        // The Go table must be complete: every model has a positive limit.
        let goModels = Limits.models()
        check(goModels.count == 28, "28 models in the Go table")
        check(goModels.allSatisfy { (Limits.value(model: $0) ?? 0) > 0 }, "every model has a limit")
        check(Limits.value(model: "deepseek-v4.1-flash") == 100, "go limit")
        check(Limits.value(model: "nope") == nil, "unknown model has no limit")

        // Docs names and API ids must land on the same key, or a fetched table
        // would never match the model ids the usage API returns.
        check(Limits.value(model: "DeepSeek V4.1 Flash") == Limits.value(model: "deepseek-v4.1-flash"),
              "docs name matches API id")
        check(Limits.normalize("Qwen3.8 Max (≤ 512K tokens)") == "qwen3-8-max", "variants share a key")

        // The docs table is fetched, so parse a slice shaped like the real page.
        let fixture = """
        <PlanTabs id="go-pricing" value="go">
        <div slot="go">

        | Model | Input | Output | Cached Read | Cached Write | Monthly limit |
        | --- | --- | --- | --- | --- | --- |
        | DeepSeek V4.1 Flash (Off-Peak) | $0.14 | $0.28 | $0.0028 | $0.14 | **$100** |
        | DeepSeek V4.1 Flash (Peak) | $0.28 | $0.56 | $0.0056 | $0.28 | **$100** |
        | Beam Free | $0 | $0 | $0 | $0 | **Unlimited**<br /><small>limited time</small> |
        </div>
        <div slot="go-plus">
        | Model | Monthly limit |
        | --- | --- |
        | DeepSeek V4.1 Flash | **$200** |
        </div>
        </PlanTabs>
        """
        let parsed = Limits.parse(fixture)
        check(parsed.count == 1, "one model after variants are merged and Unlimited is skipped")
        check(parsed["deepseek-v4-1-flash"]?.limit == 100, "parsed limit from the go slot")
        check(parsed["deepseek-v4-1-flash"]?.name == "DeepSeek V4.1 Flash", "parenthetical stripped from the name")

        // Version comparison for the update nudge.
        check(UpdateCheck.newer(latest: "v1.0.13", current: "1.0.12"), "newer patch")
        check(UpdateCheck.newer(latest: "v1.1.0", current: "1.0.13"), "newer minor")
        check(!UpdateCheck.newer(latest: "v1.0.12", current: "1.0.12"), "same version is not newer")
        check(!UpdateCheck.newer(latest: "v1.0.9", current: "1.0.10"), "older patch is not newer")
        check(UpdateCheck.newer(latest: "1.0.10", current: "1.0.9"), "numeric, not string, compare")

        print(failures == 0 ? "selftest ok" : "selftest failed: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
