import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ScannerEngine.self) var engine
    @Environment(\.openWindow) var openWindow
    /// The window's undo manager, so ⌘Z and the Edit menu work as they do
    /// anywhere else — and so a focused text field keeps its own undo.
    @Environment(\.undoManager) var undoManager
    @State var library = ScanLibrary.shared
    /// nil = the in-progress scan session; otherwise a saved PDF to preview.
    @State var selection: URL?
    @State var enlargedPage: ScannedPage?

    // Document name field
    @State var draftName = ""
    @State var lastEngineName = ""
    @FocusState var nameFieldFocused: Bool

    // Page grid
    @State var selectedPages: Set<UUID> = []
    @FocusState var gridFocused: Bool
    @AppStorage("thumbnailSize") var thumbnailSize = 160.0
    @State var pinchScale: CGFloat = 1
    /// Where dragged pages would land: beside this page, on this side.
    @State var pageDropTarget: PageDropTarget?
    /// A grid cell's width; adaptive columns are all one width.
    @State var pageCellWidth: CGFloat = 160
    @State var sizeEstimator = PDFSizeEstimator()

    // Sidebar inline rename
    @State var renamingDocumentID: UUID?
    @State var renameDraft = ""
    @State var renamePendingID: UUID?
    @FocusState var renameFieldFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .frame(minWidth: 780, minHeight: 480)
        .toolbar { toolbarContent }
        .navigationTitle("Cendatur")
        .navigationSubtitle(subtitle)
        .task {
            WindowOpener.shared.openWindowAction = openWindow
            // The first-run panel opens on the default folder, which is the
            // iCloud one when there is one — so wait to find out.
            await engine.iCloudLookup?.value
            promptForDestinationIfFirstRun()
            library.setMonitoredFolder(engine.destinationURL)
        }
        .onChange(of: engine.destinationURL) {
            library.setMonitoredFolder(engine.destinationURL)
        }
        .onChange(of: engine.documentURL) {
            library.refresh()
            if engine.documentURL != nil { selection = nil }
        }
        .onChange(of: engine.pages.count) { library.refresh() }
        .onChange(of: library.documents) {
            // The previewed scan may have been deleted or moved away; don't
            // keep showing a file that no longer exists.
            guard let selected = selection else { return }
            let stillKnown =
                library.documents.contains { $0.url == selected }
                || engine.documentURL == selected
                || engine.backgroundDocuments.contains { $0.url == selected }
            if !stillKnown { selection = nil }
        }
        .onChange(of: engine.documentDisplayName) { _, newName in
            // Follow the engine's name unless the user is mid-edit.
            if draftName == lastEngineName { draftName = newName }
            lastEngineName = newName
        }
        .onChange(of: engine.status) { _, newStatus in
            // A fresh document's scan just started: offer the proposed name,
            // focused and fully selected, so typing + return renames it.
            if case .scanning = newStatus, engine.pages.isEmpty, selection == nil {
                draftName = engine.documentDisplayName
                lastEngineName = draftName
                nameFieldFocused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
                }
            }
        }
        .sheet(item: $enlargedPage) { page in
            pagePreview(page)
        }
        .focusedSceneValue(\.scanActions, menuActions)
    }

    /// The window's half of the File menu.
    var menuActions: ScanActions {
        ScanActions(
            scan: { Task { await engine.scan() } },
            done: { finalizeDocument() },
            discard: { discardScan() },
            reveal: {
                guard let url = selection ?? engine.documentURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            share: {
                guard let url = selection ?? engine.documentURL,
                    let anchor = NSApp.keyWindow?.contentView
                else { return }
                NSSharingServicePicker(items: [url])
                    .show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
            },
            deletePages: { deleteSelectedPages() },
            selectAllPages: { selectedPages = Set(engine.pages.map(\.id)) },
            movePagesEarlier: { moveSelection(earlier: true) },
            movePagesLater: { moveSelection(earlier: false) },
            rotatePages: { clockwise in rotatePages(selectedPages, clockwise: clockwise) },
            rename: { beginRenameFromMenu() },
            canScan: !engine.isBusy && engine.scannerPresent,
            canFinish: !engine.isBusy && !engine.isSaving && !engine.pages.isEmpty,
            hasDocument: engine.current != nil,
            canDeletePages: canDeletePages,
            canMovePagesEarlier: canMoveSelection(earlier: true),
            canMovePagesLater: canMoveSelection(earlier: false),
            canRotatePages: !engine.isBusy && pageGridHasKeys && canRotate(selectedPages),
            hasPages: !engine.pages.isEmpty,
            canRename: selection != nil || engine.current != nil,
            target: selection ?? engine.documentURL)
    }

    /// The page grid is what the keyboard is pointed at: it's on screen, and
    /// no text field or sheet has the keys. The grid's ⌫, ⌦ and ⎋ are caught
    /// before any view sees them, so they must stand aside whenever typing
    /// would otherwise lose the key.
    var pageGridHasKeys: Bool {
        selection == nil && enlargedPage == nil && !nameFieldFocused
            && !renameFieldFocused
    }

    var canDeletePages: Bool {
        !selectedPages.isEmpty && !engine.isBusy && pageGridHasKeys
    }

    /// Where the selected pages stand, in page order.
    var selectedIndices: [Int] {
        engine.pages.indices.filter { selectedPages.contains(engine.pages[$0].id) }
    }

    /// False where the step would change nothing: a selection that already
    /// fills the start can't go earlier, nor one filling the end later.
    func canMoveSelection(earlier: Bool) -> Bool {
        guard !selectedPages.isEmpty, !engine.isBusy, pageGridHasKeys else { return false }
        let indices = selectedIndices
        let count = engine.pages.count
        let packed = earlier
            ? Array(0..<indices.count) : Array((count - indices.count)..<count)
        return indices != packed
    }

    /// Rename whatever the window is showing: the selected saved scan opens
    /// its inline field, and the scan being built puts the caret in the name
    /// field above the pages.
    func beginRenameFromMenu() {
        if let selection,
            let document = library.documents.first(where: { $0.url == selection }) {
            renamePendingID = nil
            beginRename(document)
        } else if engine.current != nil {
            nameFieldFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
            }
        }
    }

    /// First run: ask where scans should go. The selection doubles as the
    /// sandbox grant for that folder (stored as a security-scoped bookmark);
    /// cancelling keeps the default — the app's iCloud Drive folder, or
    /// ~/Downloads without iCloud — neither of which needs a grant.
    func promptForDestinationIfFirstRun() {
        guard !engine.settings.promptedForFolder,
            engine.settings.destinationBookmark == nil
        else { return }
        // A modal panel would hang a headless test host (the app is the
        // TEST_HOST when running unit tests, including on CI).
        guard NSClassFromString("XCTestCase") == nil,
            ProcessInfo.processInfo.environment["CENDATUR_SUPPRESS_FIRST_RUN"] == nil
        else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose where Cendatur saves your scanned PDFs."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = engine.destinationURL
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            engine.setDestination(url)
        }
        engine.settings.promptedForFolder = true
    }

    var subtitle: String {
        switch engine.status {
        case .detecting: "Looking for scanner…"
        case .scanning(let page): "Scanning page \(page)…"
        case .noScanner: "Scanner not connected"
        case .diagnosing: "Running scanner diagnostics…"
        case .idle:
            if engine.isSaving {
                "Saving…"
            } else if engine.isNaming {
                "Naming…"
            } else if engine.isProcessingAnywhere {
                "Straightening…"
            } else {
                engine.scannerName ?? ""
            }
        }
    }

    /// True while there is a scan session to show or name.
    var sessionActive: Bool {
        if !engine.pages.isEmpty { return true }
        if case .scanning = engine.status { return true }
        return false
    }
}
