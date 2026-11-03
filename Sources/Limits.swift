import Foundation

// The Go model limits live in a pricing table on the docs site and move when
// OpenCode ships models, so they are fetched and cached instead of compiled in.
// The bundled table is the fallback when the page is unreachable or has been
// restructured; a model missing from both has no percentage, only spend.
enum Limits {
    // Monthly limits for the Go plan, from https://opencode.ai/docs/go/.
    static let bundled: [String: Double] = [
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

    private static let docs = URL(string: "https://opencode.ai/docs/go/")!
    private static let tableKey = "limitsTable"
    private static let namesKey = "limitsNames"
    private static let dateKey = "limitsFetched"
    private static let maxAge: TimeInterval = 24 * 60 * 60
    private static let holder = Holder()

    static var count: Int { holder.count }
    static var isDynamic: Bool { holder.isDynamic }
    static var displayNames: [String] { holder.names }

    static func models() -> [String] { holder.names }

    static func value(model: String) -> Double? { holder.table[normalize(model)] }

    // Docs say "DeepSeek V4.1 Flash", the API says "deepseek-v4.1-flash", so
    // both sides go through the same shape before they are compared.
    static func normalize(_ name: String) -> String {
        var text = stripParenthetical(name).lowercased()
        for (from, to) in [(".", "-"), (" ", "-"), ("_", "-")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        while text.contains("--") { text = text.replacingOccurrences(of: "--", with: "-") }
        return text
    }

    static func stripParenthetical(_ name: String) -> String {
        guard let range = name.range(of: "\\s*\\([^)]*\\)", options: .regularExpression) else { return name }
        return name.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Refreshes from the docs page when the cached copy is a day old. A failed
    /// fetch keeps whatever table we already have.
    static func refreshIfStale(force: Bool = false) async {
        let last = UserDefaults.standard.object(forKey: dateKey) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > maxAge else { return }
        guard let parsed = await fetch() else { return }

        holder.replace(parsed)
        let defaults = UserDefaults.standard
        defaults.set(parsed.mapValues(\.limit), forKey: tableKey)
        defaults.set(parsed.mapValues(\.name), forKey: namesKey)
        defaults.set(Date(), forKey: dateKey)
    }

    private static func fetch() async -> [String: (name: String, limit: Double)]? {
        var request = URLRequest(url: docs)
        // The docs serve markdown to this accept header, which is far easier to
        // parse than the rendered page.
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let markdown = String(data: data, encoding: .utf8)
        else { return nil }
        let parsed = parse(markdown)
        return parsed.isEmpty ? nil : parsed
    }

    /// Pulls the monthly limit column out of the `go` pricing table.
    static func parse(_ markdown: String) -> [String: (name: String, limit: Double)] {
        var inPricing = false
        var inGoSlot = false
        var table: [String: (name: String, limit: Double)] = [:]

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.contains("<PlanTabs id=\"go-pricing\"") { inPricing = true; continue }
            guard inPricing else { continue }
            if line.contains("</PlanTabs>") { break }
            if line.hasPrefix("<div slot=\"") {
                inGoSlot = line.contains("slot=\"go\"")
                continue
            }
            guard inGoSlot, line.hasPrefix("|") else { continue }

            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 8 else { continue } // empty, model, 4 prices, limit, empty
            let name = stripParenthetical(cells[1])
            guard let limit = dollars(cells[cells.count - 2]) else { continue }
            table[normalize(name)] = (name, limit)
        }
        return table
    }

    private static func dollars(_ cell: String) -> Double? {
        let digits = cell.filter { $0.isNumber || $0 == "." }
        guard !cell.lowercased().contains("unlimited"), !digits.isEmpty else { return nil }
        return Double(digits)
    }

    private final class Holder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String: Double]
        private var labels: [String: String]
        private(set) var isDynamic: Bool

        init() {
            let defaults = UserDefaults.standard
            let cached = defaults.dictionary(forKey: Limits.tableKey) as? [String: Double] ?? [:]
            let names = defaults.dictionary(forKey: Limits.namesKey) as? [String: String] ?? [:]
            isDynamic = !cached.isEmpty
            stored = cached
            labels = names
            if stored.isEmpty {
                for (id, limit) in Limits.bundled {
                    let key = Limits.normalize(id)
                    stored[key] = limit
                    labels[key] = id
                }
            }
        }

        var table: [String: Double] {
            lock.lock(); defer { lock.unlock() }
            return stored
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return stored.count
        }

        var names: [String] {
            lock.lock(); defer { lock.unlock() }
            return labels.values.sorted()
        }

        func replace(_ parsed: [String: (name: String, limit: Double)]) {
            lock.lock(); defer { lock.unlock() }
            stored = parsed.mapValues(\.limit)
            labels = parsed.mapValues(\.name)
            isDynamic = true
        }
    }
}
