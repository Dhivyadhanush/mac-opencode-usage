import Foundation

// The cask tracks `latest`, and `brew upgrade` does nothing for it, so the only
// honest way to tell someone an update exists is to ask GitHub once a day.
enum UpdateCheck {
    static let repo = "Myleshen/mac-opencode-usage"

    static func newer(latest tag: String, current: String) -> Bool {
        let latest = numbers(tag)
        let current = numbers(current)
        for index in 0..<max(latest.count, current.count) {
            let a = index < latest.count ? latest[index] : 0
            let b = index < current.count ? current[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    static func fetchLatest() async -> String? {
        guard let request = latestRequest() else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    private static func latestRequest() -> URLRequest? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func parse(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["tag_name"] as? String
    }
}
