import AppIntents
import Foundation

/// What the app and its widget extension have in common. The extension can't
/// reach the scanner or the scan library — both live in the app — so the app
/// leaves a small snapshot of its recent scans in their shared container, and
/// the widgets hand anything that needs doing back to the app.
nonisolated enum WidgetShared {
    static let recentScansKind = "RecentScans"
    static let scanControlKind = "com.twarge.cendatur.scan-control"

    /// `cendatur://scan` starts a scan; `cendatur://open/<id>` opens one.
    static let urlScheme = "cendatur"
    static let scanURL = URL(string: "\(urlScheme)://scan")!

    static func openURL(for id: UUID) -> URL {
        URL(string: "\(urlScheme)://open/\(id.uuidString)")!
    }

    struct Scan: Codable, Identifiable, Hashable {
        let id: UUID
        let name: String
        let modified: Date
    }

    /// As many scans as the largest widget shows.
    static let snapshotLimit = 6

    /// The group both processes are entitled to, named in each Info.plist
    /// after the signing team. A build signed without a team has none, and
    /// its widgets simply stay empty.
    private static var snapshotURL: URL? {
        guard
            let group = Bundle.main.object(forInfoDictionaryKey: "CendaturAppGroup") as? String,
            !group.hasPrefix("."),
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent("recent-scans.json")
    }

    static func readScans() -> [Scan] {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Scan].self, from: data)) ?? []
    }

    /// Returns whether anything was written.
    @discardableResult
    static func writeScans(_ scans: [Scan]) -> Bool {
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(scans) else {
            return false
        }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// Starts a scan from Control Center. The scanner is driven from inside the
/// app, so the intent opens it and runs there; `start` is set by the app at
/// launch and stays nil in the widget extension.
struct StartScanIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Start a Scan"
    nonisolated static let openAppWhenRun = true
    /// Shortcuts already has "Scan a Document", which returns the PDF.
    nonisolated static let isDiscoverable = false

    @MainActor static var start: (@MainActor () -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.start?()
        return .result()
    }
}
