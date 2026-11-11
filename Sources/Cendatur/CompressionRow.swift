import SwiftUI

/// The PDF's compression, and what the document will weigh at it — the row
/// under the name field. The same setting as in Settings; changing it
/// rewrites the open PDF, and the estimate follows at once, every level
/// having been sized already.
struct CompressionRow: View {
    @Environment(ScannerEngine.self) private var engine
    let estimator: PDFSizeEstimator

    var body: some View {
        // A narrow window takes the small control rather than wrapping the
        // estimate onto a second line.
        ViewThatFits(in: .horizontal) {
            row.controlSize(.regular)
            row.controlSize(.small)
        }
        .font(.callout)
        .padding(.top, 4)
        .onChange(of: engine.pages.map(PageSizingKey.init), initial: true) {
            estimator.track(engine.pages)
        }
    }

    private var row: some View {
        @Bindable var engine = engine
        return HStack(spacing: 8) {
            Text("Compression")
                .foregroundStyle(.secondary)
            Picker("Compression", selection: $engine.settings.compression) {
                ForEach(PDFCompression.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            sizeEstimate
                .fixedSize()
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var sizeEstimate: some View {
        if let estimate = estimator.estimate(
            for: engine.pages, at: engine.settings.compression) {
            HStack(spacing: 5) {
                Text("About \(Self.byteCount(estimate.bytes))")
                    .monospacedDigit()
                // Pages still to size count at the average of the rest.
                if estimate.pagesPending > 0 {
                    ProgressView().controlSize(.mini)
                }
            }
            .help(comparison)
        } else if !engine.pages.isEmpty {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Estimating size…")
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Every level side by side, for the tooltip.
    private var comparison: String {
        PDFCompression.allCases.compactMap { level in
            estimator.estimate(for: engine.pages, at: level).map {
                "\(level.rawValue): about \(Self.byteCount($0.bytes))"
            }
        }
        .joined(separator: "\n")
    }

    private static func byteCount(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}

/// What sizing a page depends on: which page, which image, and whether
/// that image is final yet.
struct PageSizingKey: Hashable {
    let id: UUID
    let image: ObjectIdentifier
    let isProcessing: Bool

    init(_ page: ScannedPage) {
        id = page.id
        image = ObjectIdentifier(page.image)
        isProcessing = page.isProcessing
    }
}
