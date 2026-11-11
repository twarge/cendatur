import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - Sidebar

    var sidebar: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if sessionActive {
                    currentScanRow
                }
                ForEach(engine.backgroundDocuments) { document in
                    processingRow(document)
                }
                ForEach(library.documents.filter { !engine.inFlightURLs.contains($0.url) }) { document in
                    DragRow(
                        url: document.url,
                        interceptsClicks: renamingDocumentID != document.id
                    ) {
                        rowClicked(document)
                    } onMoved: { url in
                        engine.documentWasMoved(url)
                        if selection == url { selection = nil }
                        library.refresh()
                    } onTrash: { trashedTo in
                        if selection == document.url { selection = nil }
                        library.refresh()
                        guard let trashedTo else { return }
                        registerUndo("Move to Trash") { _ in
                            try? FileManager.default.moveItem(
                                at: trashedTo, to: document.url)
                            library.refresh()
                        }
                    } onRename: {
                        // Deliberately without selecting the row: renaming
                        // shouldn't swap what the detail pane is showing, and
                        // navigating away would finalize an open scan.
                        renamePendingID = nil
                        beginRename(document)
                    } content: {
                        documentRow(document, isSelected: selection == document.url)
                    }
                    .frame(height: 44)
                }
                if library.documents.isEmpty && engine.pages.isEmpty {
                    Text("No scans yet")
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
            }
            .padding(8)
        }
    }

    /// Click selects; a second click on the already-selected row (after a
    /// pause, Finder-style) begins an inline rename.
    func rowClicked(_ document: ScanDocument) {
        if selection == document.url, renamingDocumentID == nil {
            renamePendingID = document.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard renamePendingID == document.id, selection == document.url else { return }
                renamePendingID = nil
                beginRename(document)
            }
        } else {
            // Navigating away finalizes the active scan into a saved
            // document — its row joins the list like any other scan.
            // Mid-scan the session must stay open, so the current-scan row
            // remains as the way back until the batch finishes.
            if selection == nil, sessionActive, !engine.isBusy {
                engine.done()
            }
            selection = document.url
            renamePendingID = nil
            commitOrCancelRename()
        }
    }

    func beginRename(_ document: ScanDocument) {
        renameDraft = document.name
        renamingDocumentID = document.id
        renameFieldFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
        }
    }

    func commitOrCancelRename() {
        renamingDocumentID = nil
        renameFieldFocused = false
    }

    func performRename(_ document: ScanDocument) {
        defer { commitOrCancelRename() }
        let cleaned = ScannerEngine.sanitizeFileName(renameDraft)
        guard !cleaned.isEmpty, cleaned != document.name else { return }
        let directory = document.url.deletingLastPathComponent()
        var destination = directory.appendingPathComponent("\(cleaned).pdf")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(cleaned) (\(counter)).pdf")
            counter += 1
        }
        do {
            try FileManager.default.moveItem(at: document.url, to: destination)
            let previous = document.url
            if selection == document.url { selection = destination }
            library.refresh()
            registerUndo("Rename") { _ in
                try? FileManager.default.moveItem(at: destination, to: previous)
                if selection == destination { selection = previous }
                library.refresh()
            }
        } catch {
            engine.lastError = "Couldn't rename: \(error.localizedDescription)"
        }
    }

    var currentScanRow: some View {
        Button {
            selection = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: engine.documentOpen ? "doc.badge.ellipsis" : "doc.viewfinder")
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.documentURL?.deletingPathExtension().lastPathComponent
                        ?? "Current Scan")
                        .lineLimit(1)
                    Text("\(engine.pages.count) page\(engine.pages.count == 1 ? "" : "s")"
                        + (engine.documentOpen ? " — scanning adds more" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selection == nil ? Color.accentColor.opacity(0.18) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let url = engine.documentURL {
                Button("Copy PDF") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                ShareLink(item: url)
                Divider()
            }
            Button("Discard Scan", role: .destructive) { discardScan() }
        }
    }

    /// Throws away the scan in progress — the PDF goes to the Trash.
    func discardScan() {
        let discarded = engine.discardCurrent()
        selection = nil
        selectedPages = []
        draftName = ""
        guard let discarded else { return }
        registerUndo("Discard Scan") { engine in
            engine.restore(discarded)
            selection = nil
        }
    }

    /// A finalized document whose straightening/saving is still draining.
    func processingRow(_ document: ActiveDocument) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(document.displayName.isEmpty ? "Processing…" : document.displayName)
                    .lineLimit(1)
                Text("Straightening \(document.processingRemaining) page\(document.processingRemaining == 1 ? "" : "s")…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 44)
    }

    func documentRow(_ document: ScanDocument, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                if renamingDocumentID == document.id {
                    TextField("Name", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .focused($renameFieldFocused)
                        .onSubmit { performRename(document) }
                        .onExitCommand { commitOrCancelRename() }
                } else {
                    Text(document.name)
                        .lineLimit(1)
                }
                Text(document.modified.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
    }
}
