import AppIntents
import SwiftUI
import WidgetKit

@main
struct CendaturWidgets: WidgetBundle {
    var body: some Widget {
        RecentScansWidget()
        if #available(macOS 26.0, *) {
            ScanControl()
        }
    }
}

// MARK: - Scan control

/// A Scan button for Control Center and the menu bar. Like every control it
/// appears only once someone adds it there.
@available(macOS 26.0, *)
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetShared.scanControlKind) {
            ControlWidgetButton(action: StartScanIntent()) {
                Label("Scan", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Scan")
        .description("Scans whatever is in the feeder.")
    }
}

// MARK: - Recent scans

struct RecentScansEntry: TimelineEntry {
    let date: Date
    let scans: [WidgetShared.Scan]

    static let placeholder = RecentScansEntry(
        date: .now,
        scans: [
            .init(id: UUID(), name: "Electricity Bill", modified: .now.addingTimeInterval(-900)),
            .init(id: UUID(), name: "Lease Renewal", modified: .now.addingTimeInterval(-86_400)),
            .init(id: UUID(), name: "Tax Form", modified: .now.addingTimeInterval(-259_200)),
        ])
}

/// One entry, replaced whenever the app saves, renames or loses a scan — the
/// app reloads the timeline itself, so there is nothing to schedule.
struct RecentScansProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentScansEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (RecentScansEntry) -> Void) {
        completion(context.isPreview ? .placeholder : current())
    }

    func getTimeline(
        in context: Context, completion: @escaping @Sendable (Timeline<RecentScansEntry>) -> Void
    ) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> RecentScansEntry {
        RecentScansEntry(date: .now, scans: WidgetShared.readScans())
    }
}

struct RecentScansWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetShared.recentScansKind, provider: RecentScansProvider()
        ) { entry in
            RecentScansView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Scans")
        .description("Your latest scans, and a button to start another.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentScansView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentScansEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: list(rows: 6)
        default: list(rows: 3)
        }
    }

    /// The small size can't hold separate tap targets, and a tap anywhere
    /// that started the feeder would be a surprise — so it only shows the
    /// latest scan, and opens the app.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "doc.viewfinder")
                .font(.title2)
                .foregroundStyle(.tint)
            Spacer(minLength: 0)
            if let latest = entry.scans.first {
                Text(latest.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(latest.modified, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No scans yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func list(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Scans")
                    .font(.headline)
                Spacer()
                Link(destination: WidgetShared.scanURL) {
                    Label("Scan", systemImage: "doc.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.18), in: Capsule())
                }
            }
            if entry.scans.isEmpty {
                Spacer(minLength: 0)
                Text("Scans you make will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.scans.prefix(rows)) { scan in
                    Link(destination: WidgetShared.openURL(for: scan.id)) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(scan.name)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(scan.modified, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
