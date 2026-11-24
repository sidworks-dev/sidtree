# SidTree

Fast, native macOS Git client (SwiftUI + AppKit) — a SourceTree replacement in the Sidworks / BerryPath style.

## Install / update

Download the latest zip from [Releases](https://github.com/sidworks-dev/sidtree/releases), unzip and move `SidTree.app` to `/Applications`.
SidTree checks for updates itself (*SidTree → Check for Updates…*). The repository is private, so updates use your GitHub CLI login (`gh auth login`).

## Build

Only the Xcode Command Line Tools are needed:

```bash
./scripts/build.sh          # release build → build/SidTree.app
./scripts/build.sh debug    # debug build
cp -R build/SidTree.app /Applications/   # optional install
```

`scripts/sidtree [path]` opens a repository from the terminal (`open -a SidTree`).

## Releasing

1. Add a `## [x.y.z] - date` section to `CHANGELOG.md` (shown in the app's *What's New*).
2. Commit, then run `scripts/release.sh x.y.z`.
3. GitHub Actions builds the app and publishes the release with those notes; running apps offer the update.

Every push to `main` is built by CI as well (artifact kept for 14 days).
The app icon is generated from the Sidworks logo with `scripts/make-icon.swift`.

## Features

- History with commit graph, ref badges (local/remote/tags, ahead/behind), hashes, author, dates
  - All/current branch, show remote branches, date/ancestor order, search, lazy loading (10k+ commits)
  - Context menu: checkout, merge, rebase, new branch/tag, reset (soft/mixed/hard), revert, cherry-pick, copy SHA, delete branch
- File status: staged/unstaged lists with checkboxes, multi-select (⌘/⇧), stage/unstage/discard per file and per hunk
- Commit box with amend and "push after commit"
- Pull, Push (choose remote + remote branch name per branch, track, tags, force-with-lease), Fetch (+ auto-fetch)
- Branches: create, delete (local/remote), rename, double-click to checkout (remote → tracking branch)
- Merge (no-ff, squash, no-commit), rebase, stash (apply/pop/delete), tags
- Merge/rebase conflict banner with abort/continue and resolve ours/theirs
- Live refresh via FSEvents, light/dark/system theme, recent repositories dashboard, clone
- AI commit messages via the local Claude Code or Codex CLI (optional, Settings → AI)
- Update checker and What's New from `CHANGELOG.md`

## Shortcuts

| | |
|---|---|
| ⌘O / ⌘N | Open repository / new window |
| ⌘1 / ⌘2 | File status / history |
| ⇧⌘C / ⌘↩ | Commit / confirm commit |
| ⇧⌘L / ⇧⌘P / ⇧⌘F | Pull / push / fetch |
| ⇧⌘B / ⇧⌘M / ⇧⌘S / ⇧⌘T | Branch / merge / stash / tag |
| ⌘R | Refresh |
