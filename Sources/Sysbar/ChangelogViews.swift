import Foundation
import SysbarCore
import SwiftUI

/// The changelog the app was built with: `CHANGELOG.md`, copied into its resources by `bundle.sh`.
/// Read once, on first use. A build run straight from `swift build` has none.
enum BundledChangelog {
    static let releases: [ChangelogRelease] = {
        guard
            let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return Changelog.parse(text)
    }()

    /// The notes of the running version, if the changelog has them.
    static var current: ChangelogRelease? {
        Changelog.release(AppVersion(AppIdentity.shortVersion), in: releases)
    }
}

/// A release's changes as a short bulleted list.
struct ReleaseNotesList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
