import Foundation

/// Attribution for the MIT-licensed interface from which this package derives.
public enum NoctisChatAttribution {
    public static let sourceURL = "https://github.com/bryanrg22/chatgpt-ios-ui"
    public static let sourceRevision = "dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1"

    public static var licenseText: String {
        guard let url = Bundle.module.url(forResource: "ChatGPTUI-MIT", withExtension: "txt") else {
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
