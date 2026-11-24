# Changelog

All notable changes to SidTree. Newest first; the app shows these notes in **What's New** after an update.

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
