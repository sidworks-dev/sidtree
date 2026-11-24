# Changelog

All notable changes to SidTree. Newest first; the app shows these notes in **What's New** after an update.

## [Unreleased]

## [0.3.0] - 2026-11-24

### Added
- Select multiple files with a drag-selection rectangle in the file lists, with edge scrolling and Command/Shift modifiers
- Commit action dropdown with Commit and Commit & Push, remembered separately for each repository

### Changed
- Warmer, lighter dark-mode surfaces with softer text and diff colors

## [0.2.0] - 2026-11-24

### Added
- Drag files between Staged and Unstaged to stage or unstage them, including a multi-selection
- Check for updates on startup (Settings → General), with a Check Now button
- One-line install without the macOS download warning: `scripts/install.sh`

## [0.1.1] - 2026-11-24

### Added
- Clear error dialogs that explain what went wrong, list the files involved and offer the next step, such as **Stash & Switch** when local changes block a checkout
- Disk image installer: open the `.dmg` and drag SidTree to Applications

### Changed
- AI commit messages are one simple line by default, are prepared in the background and can switch model from the Generate menu

## [0.1.0] - 2026-11-24

### Added
- History with a commit graph, branch/tag/remote badges, ahead/behind counts, hashes, authors and dates
- File status with staged and unstaged files: stage, unstage and discard per file or per hunk
- Commit with amend and "push after commit"
- Pull, push (pick the remote branch name per branch), fetch and automatic fetching
- Branches: create, delete, rename and double-click to checkout; merge, rebase, stash and tags
- Conflict banner for merges and rebases with abort, continue and resolve ours/theirs
- AI commit messages with your local Claude Code or Codex CLI, with model picker and editable instruction
- Repository dashboard with recent projects, clone, light/dark theme
- Update checker and this What's New window
- Universal app for Apple Silicon and Intel Macs; drop a folder on the app icon to open it

### Performance
- Commit-graph optimisation: history of large repositories loads up to 10× faster
- History appears within ~100 ms; 40,000 commits are parsed in ~15 ms
- File-system changes inside ignored folders (caches, builds) no longer trigger refreshes
