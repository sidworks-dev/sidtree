# Changelog

All notable changes to SidTree. Newest first; the app shows these notes in **What's New** after an update.

## [Unreleased]

## [0.5.2] - 2026-11-24

### Added
- Drag one or more staged or unstaged files into editors such as PhpStorm to open them, while retaining drag-to-stage and drag-to-unstage

## [0.5.1] - 2026-11-24

### Changed
- File lists show repository-relative paths in one line, with the directory before the filename, like SourceTree

## [0.5.0] - 2026-11-24

### Added
- Open projects from Terminal with `sidtree`, `sidtree .` or `sidtree /path/to/project`, including paths to files or repository subdirectories
- **Install Command Line Tools…** in the SidTree menu; the Terminal installer also installs the command automatically
- CLI help and version options, with automated checks for launching and safe installation
- Opening an already open project from Terminal brings its window to the front

### Fixed
- The Commit action dropdown stays open when clicked and remains available when the main button is disabled

### Changed
- Removed the checkmark before the Commit button's label

## [0.4.2] - 2026-11-24

### Fixed
- ⌘A now selects all files in the staged or unstaged list
- Short diffs start at the top of the diff view
- The logo is sharp at every size

### Changed
- AI commit messages describe the overall purpose when many files change, without vague words
- Removed the "0 staged" label next to the Commit button
- New (untracked) files show a + instead of a ?
- Code quality checks: no compiler warnings, SwiftLint and ShellCheck, enforced in CI

## [0.4.1] - 2026-11-24

### Added
- Right-click the SidTree icon in the Dock to open one of your recent repositories, or open a new one

### Fixed
- Switching branches no longer scrolls the selected commit under the history's column header
- Closing the last repository window shows the start screen instead of leaving SidTree without a window

## [0.4.0] - 2026-11-24

### Added
- Edit tags: rename, move to another commit or change the message, locally and on the remote
- Delete tags here and, if you like, from the remote as well
- **Move Tag Here** in the history context menu
- ⌘A selects all files in the staged or unstaged list; ↑/↓ move through files and Space stages or unstages the selection

### Changed
- The Commit button shows a spinner and **Processing…** while committing or pushing
- Releases are built only when `VERSION` changes
- Refreshed screenshots in the README

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
