import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - Detail

    @ViewBuilder
    var detail: some View {
        if let selection {
            PDFPreview(url: selection) {
                // The file became unopenable while shown — drop it from the
                // list; the library change clears the selection below.
                library.refresh()
            }
            .ignoresSafeArea()
        } else if !sessionActive {
            emptyState
        } else {
            let cellSize = min(420, max(80, thumbnailSize * pinchScale))
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: cellSize, maximum: cellSize * 1.35),
                            spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(Array(engine.pages.enumerated()), id: \.element.id) { index, page in
                        pageCell(page, number: index + 1, size: cellSize)
                    }
                    if case .scanning = engine.status {
                        liveScanCell(size: cellSize)
                    }
                }
                .padding()
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in pinchScale = value.magnification }
                    .onEnded { _ in
                        thumbnailSize = min(420, max(80, thumbnailSize * pinchScale))
                        pinchScale = 1
                    }
            )
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .background {
                PageGridKeys(
                    canDelete: canDeletePages,
                    canDeselect: !selectedPages.isEmpty && pageGridHasKeys,
                    delete: { deleteSelectedPages() },
                    deselect: { selectedPages = [] })
            }
            .safeAreaInset(edge: .top) { documentHeader }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
    }

    /// One step earlier or later for the selection, gathered into a run if it
    /// was spread out: in ahead of the page before its first, or after the
    /// page following its last.
    func moveSelection(earlier: Bool) {
        let indices = selectedIndices
        guard let first = indices.first, let last = indices.last else { return }
        movePages(selectedPages, toOffset: earlier ? first - 1 : last + 2)
    }

    /// Dropped pages go in beside the page they were dropped on, and stay
    /// selected, as Finder leaves dropped files.
    func dropPages(_ ids: [UUID], beside page: ScannedPage, after: Bool) {
        guard let index = engine.pages.firstIndex(where: { $0.id == page.id }) else { return }
        movePages(Set(ids), toOffset: index + (after ? 1 : 0))
        selectedPages = Set(ids).intersection(engine.pages.map(\.id))
    }

    /// Whether any of these pages can turn: one still being straightened
    /// can't until that's done.
    func canRotate(_ ids: Set<UUID>) -> Bool {
        engine.pages.contains { ids.contains($0.id) && !$0.isProcessing }
    }

    func rotatePages(_ ids: Set<UUID>, clockwise: Bool) {
        guard let rotation = engine.rotatePages(withIDs: ids, clockwise: clockwise) else {
            return
        }
        registerUndo(rotation.ids.count == 1 ? "Rotate Page" : "Rotate Pages") { engine in
            engine.restore(rotation)
        }
    }

    func movePages(_ ids: Set<UUID>, toOffset offset: Int) {
        guard let order = engine.movePages(withIDs: ids, toOffset: offset) else { return }
        registerUndo(ids.count == 1 ? "Move Page" : "Move Pages") { engine in
            engine.restore(order)
        }
    }

    /// What dragging a page carries: the whole selection, in page order,
    /// when the page is part of it; otherwise that page alone.
    func dragPayload(for page: ScannedPage) -> PageDrag {
        guard selectedPages.contains(page.id) else { return PageDrag(ids: [page.id]) }
        return PageDrag(ids: engine.pages.map(\.id).filter(selectedPages.contains))
    }

    func deleteSelectedPages() {
        guard !selectedPages.isEmpty else { return }
        let deletion = engine.deletePages(withIDs: selectedPages)
        selectedPages = []
        guard let deletion else { return }
        registerUndo("Delete Pages") { engine in engine.restore(deletion) }
    }

    /// Registers an inverse for a destructive action. The handler runs on the
    /// main actor: undo arrives through the menu, which is already there.
    func registerUndo(
        _ name: String, _ inverse: @escaping (ScannerEngine) -> Void
    ) {
        guard let undoManager else { return }
        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: ScannerEngine.shared) { engine in
            MainActor.assumeIsolated { inverse(engine) }
        }
    }

    var documentHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam")
                    .foregroundStyle(.secondary)
                TextField("Document name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { finalizeDocument() }
                    .disabled(engine.isSaving)
                Text(".pdf")
                    .foregroundStyle(.secondary)
                Button("Discard", role: .destructive) { discardScan() }
                    .disabled(engine.isBusy || engine.isSaving)
                    .help("Throw this scan away — the PDF moves to the Trash")
                Button("Done") { finalizeDocument() }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isBusy || engine.isSaving || engine.pages.isEmpty)
                    .help("Commit the name and finish — shows the saved PDF")
            }
            .font(.title3)

            CompressionRow(estimator: sizeEstimator)

            // Always laid out, even when empty: the header must not jump as
            // work starts and finishes.
            HStack(spacing: 5) {
                if let activity = engine.activity {
                    ProgressView()
                        .controlSize(.small)
                    Text(activity)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 16, alignment: .leading)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Done: commit the typed name, finalize the document, and switch the
    /// view to the finished PDF.
    func finalizeDocument() {
        engine.renameDocument(to: draftName)
        nameFieldFocused = false
        guard !engine.isBusy, !engine.pages.isEmpty else { return }
        let finishedURL = engine.documentURL
        engine.done()
        selection = finishedURL
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Ready to Scan")
                .font(.title2.weight(.semibold))
            Text(
                "Load paper, then press Scan here or the button on the scanner.\n"
                    + "PDFs are saved to \(engine.destinationDisplay).\n"
                    + "Settings are in Cendatur ▸ Settings (⌘,)."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            if engine.feederWasEmpty {
                Label("The feeder was empty — load paper and try again.", systemImage: "tray")
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
            if let error = engine.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func pageCell(_ page: ScannedPage, number: Int, size: CGFloat) -> some View {
        let isSelected = selectedPages.contains(page.id)
        // What the context menu's moves act on, as Delete does: the selection
        // when this page is part of it, else this page.
        let targets = isSelected ? selectedPages : [page.id]
        let targetIndices = engine.pages.indices.filter { targets.contains(engine.pages[$0].id) }
        let dropSide = pageDropTarget?.pageID == page.id ? pageDropTarget?.after : nil
        return VStack(spacing: 6) {
            Image(nsImage: page.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: size * 1.4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 3 : 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                // Found blank: it stays in view until its batch finishes, then
                // leaves for the count in the bottom bar.
                .opacity(page.isBlank ? 0.5 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if page.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(5)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(4)
                    } else if page.isBlank {
                        Text("Blank")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(4)
                    }
                }
                // Where a drop would put the pages: a bar in the gap on that
                // side, half the grid spacing out.
                .overlay(alignment: dropSide == true ? .trailing : .leading) {
                    if let dropSide {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 4)
                            .padding(.vertical, 4)
                            .offset(x: dropSide ? 10 : -10)
                    }
                }
                .onTapGesture(count: 2) { enlargedPage = page }
                .onTapGesture {
                    let commandHeld =
                        NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
                    if commandHeld {
                        if isSelected {
                            selectedPages.remove(page.id)
                        } else {
                            selectedPages.insert(page.id)
                        }
                    } else {
                        selectedPages = [page.id]
                    }
                    gridFocused = true
                }
            Text("Page \(number)" + (page.snappedSizeName.map { " · \($0)" } ?? ""))
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if width != pageCellWidth { pageCellWidth = width }
        }
        .draggable(dragPayload(for: page)) {
            PageDragPreview(
                image: page.thumbnail, count: isSelected ? selectedPages.count : 1)
        }
        .onDrop(
            of: [.cendaturPages],
            delegate: PageDropDelegate(
                pageID: page.id, width: pageCellWidth, target: $pageDropTarget,
                isEnabled: !engine.isBusy
            ) { ids, after in
                dropPages(ids, beside: page, after: after)
            })
        .contextMenu {
            Button("View Larger") { enlargedPage = page }
            Divider()
            Button("Rotate Left") { rotatePages(targets, clockwise: false) }
                .disabled(engine.isBusy || !canRotate(targets))
            Button("Rotate Right") { rotatePages(targets, clockwise: true) }
                .disabled(engine.isBusy || !canRotate(targets))
            Divider()
            Button("Move to Start") { movePages(targets, toOffset: 0) }
                .disabled(engine.isBusy || targetIndices == Array(0..<targetIndices.count))
            Button("Move to End") { movePages(targets, toOffset: engine.pages.count) }
                .disabled(
                    engine.isBusy
                        || targetIndices
                            == Array((engine.pages.count - targetIndices.count)..<engine.pages.count))
            Divider()
            Button(
                isSelected && selectedPages.count > 1
                    ? "Delete \(selectedPages.count) Pages" : "Delete Page",
                role: .destructive
            ) {
                if isSelected {
                    deleteSelectedPages()
                } else {
                    engine.deletePage(page)
                }
            }
        }
    }

    /// The page currently feeding through the scanner, growing as rows arrive.
    func liveScanCell(size: CGFloat) -> some View {
        VStack(spacing: 6) {
            Group {
                if let live = engine.livePageImage {
                    Image(nsImage: NSImage(cgImage: live, size: .zero))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .aspectRatio(0.77, contentMode: .fit)
                        .overlay { ProgressView() }
                }
            }
            .frame(maxHeight: size * 1.4)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            if let fraction = engine.livePageFraction {
                ProgressView(value: fraction)
                    .controlSize(.small)
                    .frame(maxWidth: size * 0.8)
            } else {
                Text("Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func pagePreview(_ page: ScannedPage) -> some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: page.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 900, maxHeight: 1100)
            }
            Divider()
            HStack {
                Spacer()
                Button("Close") { enlargedPage = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    var bottomBar: some View {
        HStack {
            Text("\(engine.pages.count) page\(engine.pages.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            if let skipped = engine.current?.skippedBlankPages.count, skipped > 0 {
                Text("· \(skipped) blank page\(skipped == 1 ? "" : "s") skipped")
                    .foregroundStyle(.secondary)
                Button("Put Back") { engine.restoreSkippedBlankPages() }
                    .buttonStyle(.link)
                    .disabled(engine.isBusy)
                    .help("Return the skipped pages to where they were scanned")
            }
            if let error = engine.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(.bar)
    }
}
