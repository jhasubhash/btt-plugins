# BetterTouchTool Plugins

A personal collection of [BetterTouchTool](https://folivora.ai) plugins written
in Swift. Most are **Launcher** plugins that hook into BTT's universal launcher
surface; one is an **Action** plugin invoked from triggers.

All plugins are AI-managed sources — edit the `.swift` file in this repo and
BTT recompiles the corresponding `.btt*plugin` bundle on disk automatically.

---

## Plugins

| Plugin | Type | What it does |
| --- | --- | --- |
| [Jira Issues](#jira-issues) | Launcher | Browse issues assigned to / reported by / watched by you, or run any JQL |
| [GitHub PR Monitor](#github-pr-monitor) | Launcher | Lists open PRs and review requests for a fixed GitHub repo |
| [Stock Prices](#stock-prices) | Launcher | Quote lookup with sparkline + change/period stats |
| [Cursor Launcher](#cursor-launcher) | Launcher | Quick-open recent Cursor workspaces |
| [VS Code Launcher](#vs-code-launcher) | Launcher | Quick-open recent VS Code workspaces |
| [Copy Path / URL](#copy-path--url) | Action | Copies the front app's document path or the active browser tab's URL |

All launcher plugins surface as a single entry in BTT's universal launcher:

![Launcher entry](docs/screenshots/launcher.png)

---

### Jira Issues

Browse and search your Jira issues without leaving the launcher.

- Four built-in tabs: **Assigned to me**, **Reported by me**, **Watching**, **Custom JQL**
- Inline filter — just start typing in the launcher search box; the list narrows live across key, summary, status, and type
- ↑/↓ to navigate, **Return** to open in browser
- `⌘R` Refresh · `⌘,` Settings · `⌘U` Copy URL · `⌘K` Copy key
- Surface size is remembered across invocations
- Auth via Jira Personal Access Token (set in the in-app Settings popover or via the `JIRA_TOKEN` env var)

![Jira issue list](docs/screenshots/jira-issues.png)
![Jira connection settings](docs/screenshots/jira-settings.png)

Source: [JiraLauncherPlugin.swift](JiraLauncherPlugin.swift)

---

### GitHub PR Monitor

At-a-glance view of your open pull requests and review requests on a specific
repo (currently `Adobe-CreativeCloud/photoshop` — change the constant
`PRViewModel.repo` to retarget).

- Two sections: **My Open PRs** and **Review Requested**
- Type in the launcher search box to filter by title / number / author
- ↑/↓ to navigate, **Return** to open the PR
- Uses the `gh` CLI under the hood, so it inherits your existing auth
- Surface size is remembered across invocations

![GitHub PR list](docs/screenshots/github-prs.png)

Source: [GitHubPRMonitor.swift](GitHubPRMonitor.swift)

---

### Stock Prices

Look up any ticker and see a sparkline plus key stats.

- Type the symbol in the launcher search box; press **Return** to open the detail surface
- Period switcher: 1D · 5D · 1M · 3M · 6M · 1Y · 5Y
- Hover the sparkline to reveal price at that point
- Change / change% / previous close / current price summary
- Surface size is remembered across invocations

![Stock detail view](docs/screenshots/stock-prices.png)

Source: [StockPrices.swift](StockPrices.swift)

---

### Cursor Launcher

Lists recent [Cursor](https://cursor.sh) workspaces from the same `Storage.json`
file the editor uses, so the order matches the editor's "Recent" menu. Select
to open in Cursor.

Source: [CursorLauncher.swift](CursorLauncher.swift)

---

### VS Code Launcher

Same as the Cursor launcher, but for Visual Studio Code. Reads from VS Code's
`storage.json` and opens via the `code` CLI.

Source: [VSCodeLauncher.swift](VSCodeLauncher.swift)

---

### Copy Path / URL

A BTT **Action** (not a launcher) — bind it to a trigger and it copies the
right thing for the front-most app:

- Browsers (Safari, Chrome, Arc, Edge, Brave, Vivaldi, Opera, Firefox, **Dia**, Kagi, …) → current tab URL
- Finder → POSIX path of the selection, or the front Finder window's folder
- Anything else → the front document's path (via AX / AppleScript)

Multiple resolution strategies are tried in order (AppleScript → `AXURL` on the WebArea → address-bar text field → `AXDocument`) and the most specific result wins. This handles SPA navigations (e.g. YouTube videos) where the document URL would otherwise be stale.

Source: [CopyPathAction.swift](CopyPathAction.swift)

---

## Shared UX features

All launcher plugins share a few niceties:

- **Type-anywhere search** — printable keystrokes inside any surface are redirected to the launcher's external search box, so you never need to click it.
- **Keyboard navigation** — ↑/↓ moves the selection, **Return** opens it, **Esc** goes back.
- **Persisted surface size** — resize once and the size sticks across re-invocations (stored in `UserDefaults`).
- **Auto-select first row** — once the async fetch completes, the first row is selected so arrow keys work immediately.

---

## Repo layout

```
.
├── *.swift                            # plugin sources (one file per plugin)
├── *.btt(action|launcher)plugin/      # bundles BTT compiles into (do not edit by hand)
└── docs/screenshots/                  # screenshots used in this README
```

The `// BTT-Plugin-*` comments at the top of each `.swift` file tell BTT how
to build the bundle (name, identifier, type, icon, description).

## Configuration

A few plugins read from environment / `UserDefaults`:

- **Jira Issues** — `JIRA_TOKEN` env var, or set Base URL + PAT in the in-app Settings popover. JQL is also configurable.
- **GitHub PR Monitor** — uses whatever the `gh` CLI is authenticated to. Repo is currently hardcoded; edit `PRViewModel.repo` to change.
