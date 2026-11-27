import SwiftUI

extension SketchModel {

    /// Records the state before a change. `action` names the step in menus;
    /// `coalescing` folds continuous edits (typing, dragging a slider) into
    /// the step that started them while the same key keeps arriving.
    func checkpoint(_ action: String = "Change", coalescing key: String? = nil) {
        guard !openGroup else {
            return
        }
        if let key, key == lastCoalescingKey,
           Date().timeIntervalSince(lastCheckpointAt) < 1.2 {
            // Keep extending while the edit continues; a pause starts a step.
            lastCheckpointAt = Date()
            return
        }
        registerUndo(action: action, snapshot: Snapshot(objects: objects, selection: selection, marks: marks))
        lastCoalescingKey = key
        lastCheckpointAt = Date()
    }

    /// Runs a multi-step change as one undoable action. Nested checkpoints are
    /// folded into the snapshot taken here, so drawing a segment does not leave
    /// its two new endpoints behind as separate steps.
    func perform(_ action: String, _ body: () -> Void) {
        guard !openGroup else {
            body()
            return
        }
        let before = Snapshot(objects: objects, selection: selection, marks: marks)
        openGroup = true
        body()
        openGroup = false
        guard before.objects != objects || before.selection != selection || before.marks != marks else {
            return
        }
        registerUndo(action: action, snapshot: before)
    }

    /// Registers the inverse of a change about to be made. Each registration
    /// is its own top-level group so one ⌘Z takes back one step.
    func registerUndo(action: String, snapshot: Snapshot) {
        guard let undoManager else {
            return
        }
        MainActor.assumeIsolated {
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self) { model in
                model.restore(snapshot, action: action)
            }
            undoManager.setActionName(action)
            undoManager.endUndoGrouping()
        }
        if undoHistoryIndex < undoHistory.count {
            undoHistory.removeSubrange(undoHistoryIndex...)
        }
        undoHistory.append(UndoHistoryEntry(name: action))
        undoHistoryIndex = undoHistory.count
        lastCoalescingKey = nil
        lastCheckpointAt = Date()
        scheduleUndoRefresh()
    }

    /// Applies a snapshot and registers its inverse. `NSUndoManager` routes
    /// that inverse to the redo stack while undoing and the undo stack while
    /// redoing, so the manager already knows which direction runs.
    func restore(_ snapshot: Snapshot, action: String) {
        guard let undoManager else {
            return
        }
        let current = Snapshot(objects: objects, selection: selection, marks: marks)
        objects = snapshot.objects
        selection = snapshot.selection
        marks = snapshot.marks
        smartGuides = []
        lastCoalescingKey = nil
        MainActor.assumeIsolated {
            if undoManager.isUndoing {
                undoHistoryIndex = max(0, undoHistoryIndex - 1)
            } else if undoManager.isRedoing {
                undoHistoryIndex = min(undoHistory.count, undoHistoryIndex + 1)
            }
            undoManager.registerUndo(withTarget: self) { model in
                model.restore(current, action: action)
            }
            undoManager.setActionName(action)
            statusMessage = undoManager.isUndoing ? "Undo \(action)" : "Redo \(action)"
        }
        scheduleUndoRefresh()
    }

    /// A document swap or recovery must not continue coalescing into the
    /// previous document's edit.
    func resetTransientEditingState() {
        openGroup = false
        lastCoalescingKey = nil
    }

    /// Loading a different document starts a fresh history: snapshots hold
    /// objects and selection only, so undoing across a swap would leave the
    /// window pointing at the wrong file.
    func resetHistory() {
        if let undoManager {
            MainActor.assumeIsolated {
                undoManager.removeAllActions()
            }
        }
        undoHistory.removeAll()
        undoHistoryIndex = 0
        resetTransientEditingState()
        scheduleUndoRefresh()
    }

    func undo() {
        guard let undoManager, undoManager.canUndo else {
            return
        }
        MainActor.assumeIsolated {
            undoManager.undo()
        }
        clearSmartGuides()
    }

    func redo() {
        guard let undoManager, undoManager.canRedo else {
            return
        }
        MainActor.assumeIsolated {
            undoManager.redo()
        }
        clearSmartGuides()
    }

    /// Walks the undo stack until the panel's selected step is current.
    func travelHistory(to index: Int) {
        let target = min(max(index, 0), undoHistory.count)
        while undoHistoryIndex > target, canUndo {
            undo()
        }
        while undoHistoryIndex < target, canRedo {
            redo()
        }
    }

    /// Undo state lives in NSUndoManager, not in a published property, so
    /// views that show it (the toolbar) re-render from its own notifications.
    func observeUndoState(of manager: UndoManager) {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        let names: [Notification.Name] = [
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange
        ]
        undoObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleUndoRefresh()
                }
            }
        }
    }

    /// Notifications can fire while SwiftUI is updating views, and publishing
    /// then is undefined. Defer one change to the next turn and coalesce the
    /// burst of checkpoints a single edit produces.
    func scheduleUndoRefresh() {
        guard !undoRefreshPending else {
            return
        }
        undoRefreshPending = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            undoRefreshPending = false
            undoRevision &+= 1
        }
    }

    var canUndo: Bool {
        _ = undoRevision
        guard let undoManager else {
            return false
        }
        return MainActor.assumeIsolated {
            undoManager.canUndo
        }
    }

    var canRedo: Bool {
        _ = undoRevision
        guard let undoManager else {
            return false
        }
        return MainActor.assumeIsolated {
            undoManager.canRedo
        }
    }

    /// The action ⌘Z would take back, for menu titles and status text.
    var undoActionName: String? {
        _ = undoRevision
        guard let undoManager else {
            return nil
        }
        let name = MainActor.assumeIsolated {
            undoManager.undoActionName
        }
        return name.isEmpty ? nil : name
    }

    var redoActionName: String? {
        _ = undoRevision
        guard let undoManager else {
            return nil
        }
        let name = MainActor.assumeIsolated {
            undoManager.redoActionName
        }
        return name.isEmpty ? nil : name
    }
}
