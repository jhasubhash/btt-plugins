# Contributing changes back to `folivoraAI/BetterTouchToolPlugins`

This repo (`jhasubhash/btt-plugins`) is the upstream source for the
**community plugins** that fifafu imported into the official BetterTouchTool
plugins repository:

> https://github.com/folivoraAI/BetterTouchToolPlugins

This document is the playbook for raising a PR against that official repo to
**refresh the already-imported plugins** whenever we ship changes here.

---

## 1. Upstream layout (where our plugins already live)

Every plugin already has its own folder under `plugins/community/` with a
`README.md`, a `plugin.json`, the `.swift` source, and a `screenshots/`
folder. Mapping from this repo's source files to the upstream folders:

| Our file                          | Upstream folder                                              | Plugin identifier                              |
| --------------------------------- | ------------------------------------------------------------ | ---------------------------------------------- |
| `CopyPathAction.swift`            | `plugins/community/action-copy-path-url`                     | `com.bttuserplugin.swift.copypathaction`       |
| `CursorLauncher.swift`            | `plugins/community/launcher-cursor`                          | `com.bttuserplugin.cursor.launcher`            |
| `GitHubPRMonitor.swift`           | `plugins/community/launcher-github-pr-monitor`               | `com.bttuserplugin.github.prmonitor`           |
| `JiraLauncherPlugin.swift`        | `plugins/community/launcher-jira-issues`                     | `com.bttuserplugin.jira.launcher`              |
| `KillProcess.swift`               | `plugins/community/launcher-kill-process`                    | `com.bttuserplugin.killprocess`                |
| `NewsSearchPlugin.swift`          | `plugins/community/launcher-news-search`                     | `com.bttuserplugin.newssearch`                 |
| `QuickLinkLauncherPlugin.swift`   | `plugins/community/launcher-quick-links-jhasubhash`          | `com.folivora.launcher.quicklinks.example`     |
| `QuickTimeRecording.swift`        | `plugins/community/launcher-quicktime-recording`             | `com.bttuserplugin.quicktime.recording`        |
| `StockPrices.swift`               | `plugins/community/launcher-stock-prices`                    | `com.bttuserplugin.stockprices`                |
| `VSCodeLauncher.swift`            | `plugins/community/launcher-vscode`                          | `com.bttuserplugin.vscode.launcher`            |
| `XcodeRecentProjects.swift`       | `plugins/community/launcher-xcode-recent-projects`           | `com.bttuserplugin.xcode-recent-projects`      |

The master registry is `plugins/index.json` — we **do not** add new entries
when only updating an existing plugin; we only edit the folder contents.

Reference: the official
[`CONTRIBUTING.md`](https://github.com/folivoraAI/BetterTouchToolPlugins/blob/master/CONTRIBUTING.md)
and
[`README.md`](https://github.com/folivoraAI/BetterTouchToolPlugins/blob/master/README.md)
in the upstream repo.

---

## 2. One-time setup

```bash
# 1. Fork folivoraAI/BetterTouchToolPlugins on GitHub (via the UI) into
#    jhasubhash/BetterTouchToolPlugins, then clone the fork:
gh repo fork folivoraAI/BetterTouchToolPlugins --clone --remote
cd BetterTouchToolPlugins

# 2. Confirm remotes
git remote -v
# origin    git@github.com:jhasubhash/BetterTouchToolPlugins.git (fetch/push)
# upstream  https://github.com/folivoraAI/BetterTouchToolPlugins.git (fetch/push)
```

Keep the fork in sync before starting any new PR:

```bash
git fetch upstream
git checkout master
git merge --ff-only upstream/master
git push origin master
```

---

## 3. Per-PR workflow

For every PR that updates already-imported plugins from this repo:

### 3.1 Pick the source commit

In **this** repo (`jhasubhash/btt-plugins`), make sure everything is committed
and pushed, then capture the exact commit SHA:

```bash
cd "/Users/sujha/Library/Application Support/BetterTouchTool/Plugins"
git rev-parse HEAD
```

Note the full SHA — it goes into `plugin.json` → `origin.importedFromCommit`
in every plugin folder we touch.

### 3.2 Cut a feature branch in the fork

```bash
cd <wherever you cloned>/BetterTouchToolPlugins
git checkout -b community/refresh-jhasubhash-plugins-YYYY-MM-DD
```

A single PR can refresh multiple plugins; pick a branch name that reflects the
scope (`refresh-jhasubhash-plugins`, `refresh-jira-and-github-pr`, etc.).

### 3.3 For each plugin being refreshed

In every upstream folder we touch, do all of:

1. **Source** — copy the latest `.swift` file from this repo over the
   upstream file, preserving the filename listed in `plugin.json` →
   `entry`. Do not rename the entry file.

   ```bash
   cp "/Users/sujha/Library/Application Support/BetterTouchTool/Plugins/JiraLauncherPlugin.swift" \
      plugins/community/launcher-jira-issues/JiraLauncherPlugin.swift
   ```

2. **Screenshots** — copy any new/updated screenshots from
   `docs/screenshots/` in this repo into the upstream folder's
   `screenshots/` directory, keeping filenames that already exist where
   possible (so links in the upstream README don't break).

3. **README.md** — update the plugin's upstream README to reflect new
   features, keyboard shortcuts, settings flow, etc. Keep the upstream
   attribution block intact (it usually starts with
   `Imported from https://github.com/jhasubhash/btt-plugins ...`).

4. **plugin.json** — update **all** of:
   - `description` — keep in sync with the new README summary.
   - `permissions` — add/remove from the allowed labels if behavior
     changed (`clipboard-read`, `clipboard-write`, `file-read`,
     `file-write`, `network`, `open-url`, `shell`, `apple-script`,
     `accessibility`, `btt-variables`, `named-triggers`,
     `launcher-plugin-instances`, `user-defaults`, `process-control`,
     `spotlight`).
   - `screenshots` — list every file added/kept under `screenshots/`.
   - `reviewStatus` — set to **`submitted`** while the PR is open;
     fifafu flips it back to `community-reviewed` on merge.
   - `origin.importedFromCommit` — the SHA from step 3.1.
   - `origin.source` — make sure it points at the right file path on
     `main` (e.g.
     `https://github.com/jhasubhash/btt-plugins/blob/main/JiraLauncherPlugin.swift`).
   - Leave `schemaVersion`, `identifier`, `type`, `entry`, `author`,
     `copyright`, `license`, and `minimumBetterTouchToolVersion`
     unchanged unless they really need to move.

5. **Metadata comments in the `.swift` file** — confirm
   `// BTT-Plugin-Name`, `// BTT-Plugin-Identifier`, `// BTT-Plugin-Type`,
   and `// BTT-Plugin-Icon` still match `plugin.json`. The upstream
   reviewer rejects mismatches.

### 3.4 Compile-check locally

Same command we already use here, run from the upstream working tree on
the files you touched:

```bash
xcrun swiftc -typecheck \
  -import-objc-header /Applications/BetterTouchTool.app/Contents/Resources/BTTSwiftPluginHeader.h \
  -framework AppKit -framework SwiftUI -framework Combine \
  -target arm64-apple-macos14.0 \
  plugins/community/launcher-jira-issues/JiraLauncherPlugin.swift \
  plugins/community/launcher-github-pr-monitor/GitHubPRMonitor.swift
```

Drag the `.swift` files onto BetterTouchTool too — that is the install path the
upstream README endorses and the reviewer expects "compiles from a clean
`.swift` file" to be true.

### 3.5 Refresh the gallery catalog

After touching any `plugin.json` or screenshot, regenerate the static gallery
catalog so the GitHub Pages site stays in sync:

```bash
node tools/build-site-catalog.mjs
```

Commit the resulting changes under `site/` together with the plugin changes.

### 3.6 Commit & PR

```bash
git add plugins/community/... site/...
git commit -m "Refresh jhasubhash community plugins

- Jira Issues: Settings moved to launcher row ⌘P popover; added ⌘C copy URL
- GitHub PR Monitor: ditto, plus ⌘C copies PR URL
- Updated importedFromCommit, screenshots, READMEs, plugin.json
- Regenerated site catalog"
git push -u origin community/refresh-jhasubhash-plugins-YYYY-MM-DD
gh pr create --repo folivoraAI/BetterTouchToolPlugins \
  --base master \
  --draft \
  --title "Community: refresh jhasubhash plugin imports" \
  --body "$(cat <<'EOF'
## Summary

Refreshes the community plugins originally imported from
https://github.com/jhasubhash/btt-plugins.

### Plugins updated
- `plugins/community/launcher-jira-issues`
- `plugins/community/launcher-github-pr-monitor`
- _(list every folder touched)_

### Notable changes
- Settings flow moved from in-surface UI to the launcher row's ⌘P
  action popover (matches the QuickLinks pattern).
- Added ⌘C to copy the highlighted issue/PR URL.
- Updated screenshots and READMEs.

### Source
- Imported from commit `<SHA>` of jhasubhash/btt-plugins.
- `plugin.json` → `origin.importedFromCommit` bumped accordingly.
- `reviewStatus` set to `submitted` (please flip to `community-reviewed`
  on merge).

### Verification
- `xcrun swiftc -typecheck` passes for every touched `.swift` file.
- Plugins drag-and-drop install cleanly into BetterTouchTool.
- `node tools/build-site-catalog.mjs` regenerated; `site/` changes
  included in the diff.
EOF
)"
```

Note the `--draft` flag — keeps the PR out of fifafu's review queue until
we explicitly mark it ready (`gh pr ready <num>`).

---

## 4. Review checklist (mirrors upstream's `README.md`)

Before flipping the PR out of draft:

- [ ] Source code reads cleanly and is intentionally scoped.
- [ ] Plugin identifier is unchanged and stable.
- [ ] Metadata comments match `plugin.json`.
- [ ] File / network / shell / AppleScript / clipboard / accessibility
      behavior is documented in the plugin's README.
- [ ] Plugin does not collect or transmit unnecessary data.
- [ ] No auto-running destructive actions.
- [ ] Screenshot(s) included for any visible UI changes.
- [ ] Compiles in BetterTouchTool from a clean `.swift` file.
- [ ] `plugin.json` → `permissions` is the minimal set that's actually
      used.
- [ ] `plugin.json` → `reviewStatus` = `submitted`.
- [ ] `plugin.json` → `origin.importedFromCommit` updated.
- [ ] `tools/build-site-catalog.mjs` re-run; `site/` changes committed.

---

## 5. Useful upstream references

- Repo home: <https://github.com/folivoraAI/BetterTouchToolPlugins>
- Contributing guide: <https://github.com/folivoraAI/BetterTouchToolPlugins/blob/master/CONTRIBUTING.md>
- `_template` folder: <https://github.com/folivoraAI/BetterTouchToolPlugins/tree/master/plugins/_template>
- Existing Jira Issues entry (good baseline for our updates):
  <https://github.com/folivoraAI/BetterTouchToolPlugins/tree/master/plugins/community/launcher-jira-issues>
- Master registry: <https://github.com/folivoraAI/BetterTouchToolPlugins/blob/master/plugins/index.json>
- Plugin gallery (rendered): <https://folivoraai.github.io/BetterTouchToolPlugins/>
