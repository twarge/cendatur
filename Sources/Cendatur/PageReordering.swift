import SwiftUI
import UniformTypeIdentifiers

// MARK: - Page reordering

extension UTType {
    /// Pages dragged within the grid. Declared in Info.plist; nothing outside
    /// the app takes it, so a page can't be dropped anywhere else by mistake.
    nonisolated static let cendaturPages = UTType(exportedAs: "com.twarge.snapscan.pages")
}

/// The pages a drag carries, by ID, in page order.
nonisolated struct PageDrag: Codable, Transferable {
    let ids: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .cendaturPages)
    }
}

struct PageDropTarget: Equatable {
    let pageID: UUID
    /// After the page rather than before it.
    let after: Bool
}

/// Takes pages dropped on one page of the grid. Which half of the page the
/// pointer is over says whether they go before or after it.
struct PageDropDelegate: DropDelegate {
    let pageID: UUID
    let width: CGFloat
    @Binding var target: PageDropTarget?
    let isEnabled: Bool
    let perform: @MainActor ([UUID], Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && info.hasItemsConforming(to: [.cendaturPages])
    }

    func dropEntered(info: DropInfo) {
        target = PageDropTarget(pageID: pageID, after: isAfter(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let updated = PageDropTarget(pageID: pageID, after: isAfter(info))
        if target != updated { target = updated }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.pageID == pageID { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = isAfter(info)
        target = nil
        guard let provider = info.itemProviders(for: [.cendaturPages]).first else {
            return false
        }
        let perform = perform
        _ = provider.loadTransferable(type: PageDrag.self) { result in
            guard case .success(let drag) = result else { return }
            Task { @MainActor in perform(drag.ids, after) }
        }
        return true
    }

    private func isAfter(_ info: DropInfo) -> Bool {
        info.location.x > width / 2
    }
}

/// What follows the pointer: the page, with a count when several go along.
struct PageDragPreview: View {
    let image: NSImage
    let count: Int

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 72)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
    }
}
