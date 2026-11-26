import Foundation

/// Notices for the MIT-licensed interface and icon resources distributed by this package.
public enum NoctisChatAttribution {
    public static let sourceURL = "https://github.com/bryanrg22/chatgpt-ios-ui"
    public static let sourceRevision = "dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1"

    public static let iconSourceURL = "https://github.com/tabler/tabler-icons/tree/v3.34.1"

    public static var licenseText: String { license(named: "ChatGPTUI-MIT") }
    public static var iconLicenseText: String { license(named: "TablerIcons-MIT") }

    private static func license(named name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt") else {
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
