import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - Toolbar

    /// A setting as a binding, for the controls that change it directly.
    func setting<Value>(_ key: WritableKeyPath<ScanSettings, Value>) -> Binding<Value> {
        Binding(
            get: { engine.settings[keyPath: key] },
            set: { engine.settings[keyPath: key] = $0 })
    }

    /// Auto always crops to the sheet, so under Auto the toggle shows on.
    var cropBinding: Binding<Bool> {
        Binding(
            get: { engine.settings.autocrop || engine.settings.paperSize == .auto },
            set: { engine.settings.autocrop = $0 })
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        // What changes from one stack of paper to the next. The rest — and
        // these again — are in Settings. Fixed while a scan is running: the
        // scanner and each page's processing have already taken them.
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Paper", selection: setting(\.paperSize)) {
                ForEach(PaperSize.allCases) { size in
                    Text(size.rawValue).tag(size)
                }
            }
            .disabled(engine.isBusy)
            .help("Paper size")
            Picker("Sides", selection: setting(\.source)) {
                ForEach(ScanSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            .disabled(engine.isBusy)
            .help("Which sides of each sheet to keep")
            Picker("Color", selection: setting(\.mode)) {
                ForEach(ScanMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .disabled(engine.isBusy)
            .help("Color, grayscale, or black & white")
            Picker("Resolution", selection: setting(\.resolution)) {
                ForEach(ScanSettings.resolutions, id: \.self) { dpi in
                    Text("\(dpi) dpi").tag(dpi)
                }
            }
            .disabled(engine.isBusy)
            .help("Resolution")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: cropBinding) {
                Label("Crop to Sheet", systemImage: "crop")
            }
            .disabled(engine.isBusy || engine.settings.paperSize == .auto)
            .help(
                engine.settings.paperSize == .auto
                    ? "Crop to the sheet — Auto paper size always does"
                    : "Crop each page to the sheet, for paper smaller than \(engine.settings.paperSize.rawValue)")
            Toggle(isOn: setting(\.skipBlankPages)) {
                Label("Skip Blank Pages", systemImage: "rectangle.portrait.slash")
            }
            .disabled(engine.isBusy)
            .help("Leave blank pages out of the PDF")
            Toggle(isOn: setting(\.appendScans)) {
                Label("Combine Scans", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(engine.isBusy)
            .help(
                "Add each scan to the open PDF until you press Done, "
                    + "rather than saving each as its own")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            scannerStatusIndicator
            if case .scanning = engine.status {
                Button {
                    engine.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await engine.scan() }
                } label: {
                    Label("Scan", systemImage: "scanner")
                }
                .disabled(engine.isBusy || !engine.scannerPresent)
            }
        }
    }

    var scannerStatusIndicator: some View {
        Button {
            Task { await engine.detectScanner() }
        } label: {
            if !engine.scannerPresent {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            } else if engine.status == .detecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .help(
            !engine.scannerPresent
                ? "Scanner not connected — plug in the scanner and open its feeder flap"
                : engine.status == .detecting
                    ? "Looking for scanner…"
                    : (engine.scannerName ?? "Scanner ready"))
    }
}
