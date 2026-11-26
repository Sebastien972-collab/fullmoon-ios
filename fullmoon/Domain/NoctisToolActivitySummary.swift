// Created by Sébastien DAGUIN

import Foundation

/// Extracts bounded, useful details instead of persisting raw tool payloads.
enum NoctisToolActivitySummary {
    struct Result {
        var text: String?
        var count: Int?
        var sources: [NoctisActivitySource] = []
    }

    static func input(name: String, arguments: String) -> String? {
        guard let object = object(arguments) else { return nil }
        let key: String
        switch name {
        case "web_search": key = "query"
        case "web_open": key = "url"
        case "readFile", "listFiles": key = "path"
        case "searchCode": key = "query"
        default: return nil
        }
        guard let value = object[key] as? String else { return nil }
        if key == "url" { return webURL(value)?.absoluteString }
        return clean(value, limit: 500)
    }

    static func result(name: String, result: String, isError: Bool) -> Result {
        let payload = object(result)
        if isError {
            // Unknown error bodies can contain request credentials or local data.
            // The UI uses a localized failure label when there is no safe public summary.
            return Result()
        }
        switch name {
        case "web_search":
            guard let results = payload?["results"] as? [[String: Any]] else { return Result() }
            return Result(count: results.count, sources: sources(results))
        case "web_open":
            guard let payload else { return Result() }
            return Result(text: (payload["title"] as? String).flatMap { clean($0, limit: 240) },
                          sources: sources([payload]))
        default:
            return Result()
        }
    }

    static func webURL(_ value: String) -> URL? {
        guard value.utf8.count <= 2_048,
              var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil else { return nil }
        components.fragment = nil
        // Keep source navigation useful without storing tokens or signed query parameters.
        let sensitiveNames = ["token", "access_token", "api_key", "apikey", "key", "secret", "signature", "sig"]
        if components.queryItems?.contains(where: { item in
            sensitiveNames.contains(item.name.lowercased()) || item.name.lowercased().hasPrefix("x-amz-")
        }) == true {
            components.query = nil
        }
        return components.url
    }

    private static func sources(_ results: [[String: Any]]) -> [NoctisActivitySource] {
        var seen: Set<String> = []
        return results.prefix(24).compactMap { value in
            guard let raw = value["url"] as? String, let url = webURL(raw),
                  seen.insert(url.absoluteString).inserted else { return nil }
            let title = (value["title"] as? String).flatMap { clean($0, limit: 180) }
            return NoctisActivitySource(url: url, title: title ?? url.host() ?? url.absoluteString)
        }.prefix(8).map { $0 }
    }

    private static func object(_ text: String) -> [String: Any]? {
        guard text.utf8.count <= 262_144, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func clean(_ value: String, limit: Int) -> String? {
        let text = String(String.UnicodeScalarView(value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t"
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(limit))
    }
}
