import Foundation

/// The launcher's selected row, kept by item ID so that the list highlight,
/// the detail pane and the ⌘K actions always agree on one entry.
///
/// The index is derived from the ID against the current list. A refresh of
/// the list (new clipboard entry, app index rescan, async search results)
/// keeps the same entry selected; only an explicit `reset` (the query
/// changed, the launcher was reopened) goes back to the top.
public struct ListSelection: Equatable {
    /// The selected item's ID; nil when the list is empty.
    public private(set) var id: String?
    /// Its position in the list last passed in.
    public private(set) var index: Int = 0

    public init() {}

    /// Selects the row at `index` of `ids` (clamped to the list).
    public mutating func select(index newIndex: Int, in ids: [String]) {
        guard !ids.isEmpty else { id = nil; index = 0; return }
        index = min(max(newIndex, 0), ids.count - 1)
        id = ids[index]
    }

    /// Selects the item with this ID; returns false (and changes nothing)
    /// when it isn't in the list.
    @discardableResult
    public mutating func select(id wanted: String, in ids: [String]) -> Bool {
        guard let i = ids.firstIndex(of: wanted) else { return false }
        id = wanted
        index = i
        return true
    }

    /// Back to the first row (a new query, or the launcher was reopened).
    public mutating func reset(in ids: [String]) {
        select(index: 0, in: ids)
    }

    /// The list changed under the same query: keep the selected item where
    /// it moved to. If it's gone, stay at the same position (clamped), so the
    /// neighbour of a deleted entry gets selected rather than the top row.
    public mutating func update(to ids: [String]) {
        if let id, select(id: id, in: ids) { return }
        select(index: index, in: ids)
    }
}
