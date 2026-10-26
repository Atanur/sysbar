import Foundation

/// The project's pages. Issue links fill in the version, macOS and Mac model so a report starts
/// with them; the user still sees and edits everything on GitHub before sending it.
public enum ProjectLinks {
    public static let website = URL(string: "https://sysbar.atanur.dev/")!
    public static let repository = URL(string: "https://github.com/Atanur/sysbar")!
    public static let license = URL(string: "https://github.com/Atanur/sysbar/blob/main/LICENSE")!
    /// Every release's notes, on the website.
    public static let changelog = URL(string: "https://sysbar.atanur.dev/#changelog")!
    private static let newIssue = "https://github.com/Atanur/sysbar/issues/new"

    public static func bugReport(version: String, system: String, mac: String) -> URL {
        issue(template: "bug_report.yml", fields: [("version", version), ("macos", system), ("mac", mac)])
    }

    public static func featureRequest() -> URL {
        issue(template: "feature_request.yml", fields: [])
    }

    private static func issue(template: String, fields: [(String, String)]) -> URL {
        var components = URLComponents(string: newIssue)!
        components.queryItems = [URLQueryItem(name: "template", value: template)]
            + fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}
