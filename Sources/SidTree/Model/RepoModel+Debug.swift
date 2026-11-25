import Foundation

extension RepoModel {
    /// Development aid for screenshots and checks: `SIDTREE_DEBUG_VIEW` and related variables put the
    /// repository in a known state shortly after it opens.
    func runDebugScenario() {
        if let view = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_VIEW"] {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if ProcessInfo.processInfo.environment["SIDTREE_DEBUG_SYNCING"] != nil {
                    syncing = [.fetch, .pull, .push]
                    pushingBranches = Set([currentBranch].compactMap { $0 })
                }
                if let branch = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_DELETE_BRANCH"] {
                    sheet = .deleteBranch(branch)
                    return
                }
                if let tag = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_EDIT_TAG"] {
                    sheet = .editTag(tag, target: nil)
                    return
                }
                if let branch = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_CHECKOUT"] {
                    checkout(localName: branch)
                    return
                }
                if let jumpTo = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_JUMP"],
                   let row = rows.first(where: { $0.commit.subject.contains(jumpTo) }) {
                    jump(to: row.commit.id)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if let back = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_JUMP_BACK"],
                       let top = rows.first(where: { $0.commit.subject.contains(back) }) {
                        jump(to: top.commit.id)
                    }
                    return
                }
                let wanted = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_SELECT"] ?? ""
                if view == "status" {
                    sidebarSelection = .changes
                    let wantedFile = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_FILE"] ?? ""
                    let all = status.staged + status.unstaged
                    selectStatusFile(all.first { !wantedFile.isEmpty && $0.path.contains(wantedFile) } ?? all.first)
                } else if !wanted.isEmpty, let row = rows.first(where: { $0.commit.subject.contains(wanted) }) {
                    selectCommit(row.commit.id)
                } else if rows.count > 2 {
                    selectCommit(rows[2].commit.id)
                }
            }
        }
    }
}
