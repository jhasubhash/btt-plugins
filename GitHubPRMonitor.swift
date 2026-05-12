// BTT-Plugin-Name: GitHub PR Monitor
// BTT-Plugin-Identifier: com.bttuserplugin.github.prmonitor
// BTT-Plugin-Type: Launcher
// BTT-Plugin-Icon: arrow.triangle.pull
// BTT-Plugin-Description: Browse your open GitHub PRs and review requests
// BTT-AI-Managed: true

import Cocoa
import SwiftUI

// MARK: - Models

struct GitHubPR: Identifiable {
    let id: Int
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let author: String
    let updatedAt: String
}

// MARK: - ViewModel

@MainActor
class PRViewModel: ObservableObject {
    @Published var myPRs: [GitHubPR] = []
    @Published var reviewPRs: [GitHubPR] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefreshed: Date?
    @Published var searchQuery:  String  = "" { didSet { selectedPRId = nil } }
    @Published var selectedPRId: Int?    = nil

    var filteredMyPRs:     [GitHubPR] { filterPRs(myPRs)     }
    var filteredReviewPRs: [GitHubPR] { filterPRs(reviewPRs) }
    private var allFiltered: [GitHubPR] { filteredMyPRs + filteredReviewPRs }

    static let repo = "Adobe-CreativeCloud/photoshop"

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        async let mine   = run(args: ["pr", "list",
                                      "--repo", Self.repo,
                                      "--author", "@me",
                                      "--state", "open",
                                      "--json", "number,title,url,isDraft,author,updatedAt",
                                      "--limit", "50"])
        async let review = run(args: ["pr", "list",
                                      "--repo", Self.repo,
                                      "--search", "review-requested:@me",
                                      "--state", "open",
                                      "--json", "number,title,url,isDraft,author,updatedAt",
                                      "--limit", "50"])

        let (mineResult, reviewResult) = await (mine, review)

        switch mineResult {
        case .success(let data):  myPRs = parsePRs(data)
        case .failure(let err):   errorMessage = err.localizedDescription
        }
        switch reviewResult {
        case .success(let data):  reviewPRs = parsePRs(data)
        case .failure(let err):   if errorMessage == nil { errorMessage = err.localizedDescription }
        }

        isLoading = false
        lastRefreshed = Date()
    }

    private func parsePRs(_ data: Data) -> [GitHubPR] {
        struct RawPR: Decodable {
            let number: Int
            let title: String
            let url: String
            let isDraft: Bool
            let author: AuthorObj
            let updatedAt: String
            struct AuthorObj: Decodable { let login: String }
        }
        guard let raw = try? JSONDecoder().decode([RawPR].self, from: data) else { return [] }
        return raw.map {
            GitHubPR(id: $0.number, number: $0.number, title: $0.title,
                     url: $0.url, isDraft: $0.isDraft,
                     author: $0.author.login, updatedAt: $0.updatedAt)
        }
    }

    private func run(args: [String]) async -> Result<Data, Error> {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let gh = (["/usr/local/bin/gh",
                                 "/opt/homebrew/bin/gh",
                                 "/opt/homebrew/sbin/gh"] as [String])
                        .first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                    cont.resume(returning: .failure(
                        NSError(domain: "BTTPRPlugin", code: 1,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "gh CLI not found.\nInstall via: brew install gh"])))
                    return
                }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: gh)
                proc.arguments = args

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                proc.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    if proc.terminationStatus == 0 {
                        cont.resume(returning: .success(outData))
                    } else {
                        let errStr = String(
                            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? "Unknown error"
                        cont.resume(returning: .failure(
                            NSError(domain: "BTTPRPlugin",
                                    code: Int(proc.terminationStatus),
                                    userInfo: [NSLocalizedDescriptionKey:
                                        errStr.trimmingCharacters(in: .whitespacesAndNewlines)])))
                    }
                } catch {
                    cont.resume(returning: .failure(error))
                }
            }
        }
    }

    private func filterPRs(_ prs: [GitHubPR]) -> [GitHubPR] {
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return prs }
        return prs.filter {
            $0.title.lowercased().contains(q)  ||
            String($0.number).contains(q)      ||
            $0.author.lowercased().contains(q)
        }
    }

    func navigateDown() {
        let list = allFiltered
        guard !list.isEmpty else { return }
        if let id = selectedPRId, let idx = list.firstIndex(where: { $0.id == id }) {
            selectedPRId = list[min(list.count - 1, idx + 1)].id
        } else {
            selectedPRId = list.first?.id
        }
    }

    func navigateUp() {
        let list = allFiltered
        guard !list.isEmpty else { return }
        if let id = selectedPRId, let idx = list.firstIndex(where: { $0.id == id }) {
            selectedPRId = list[max(0, idx - 1)].id
        } else {
            selectedPRId = list.last?.id
        }
    }

    func openSelected() {
        if let id = selectedPRId, let pr = allFiltered.first(where: { $0.id == id }) {
            open(pr)
        }
    }

    func open(_ pr: GitHubPR) {
        guard let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - PR Row

struct PRRowView: View {
    let pr: GitHubPR
    var isSelected: Bool = false
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text("#\(pr.number)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 46, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if pr.isDraft {
                            Text("DRAFT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.55))
                                .cornerRadius(3)
                        }
                        Text(pr.title)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(relativeTime(from: pr.updatedAt))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 6)

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundColor((isSelected || hovered) ? .accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.22) : (hovered ? Color.accentColor.opacity(0.12) : Color.clear))
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    func relativeTime(from iso: String) -> String {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        guard let date = f1.date(from: iso) ?? f2.date(from: iso) else { return "" }
        let secs = Int(-date.timeIntervalSinceNow)
        switch secs {
        case ..<60:         return "just now"
        case 60..<3600:     return "\(secs / 60)m ago"
        case 3600..<86400:  return "\(secs / 3600)h ago"
        default:            return "\(secs / 86400)d ago"
        }
    }
}

// MARK: - Section Header

struct PRSectionHeader: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.4)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(color)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
    }
}

// MARK: - Dashboard

struct PRDashboard: View {
    @StateObject private var vm = PRViewModel()
    let navProxy: NavigationProxy

    var body: some View {
        VStack(spacing: 0) {

            // ── Toolbar ──────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Adobe-CreativeCloud / photoshop")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let t = vm.lastRefreshed {
                    Text(timeStr(t))
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.7))
                }
                if vm.isLoading {
                    ProgressView().scaleEffect(0.55).frame(width: 18, height: 18)
                } else {
                    Button { Task { await vm.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Refresh")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // ── Error Banner ─────────────────────────────────────
            if let err = vm.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                    Spacer()
                    Button { Task { await vm.refresh() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
                Divider()
            }

            // ── PR Lists ─────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {

                        // My Open PRs
                        PRSectionHeader(title: "My Open PRs",
                                        icon: "person.fill",
                                        count: vm.filteredMyPRs.count,
                                        color: .blue)
                        if vm.filteredMyPRs.isEmpty {
                            Text(vm.isLoading ? "Loading…" : (vm.searchQuery.isEmpty ? "No open PRs 🎉" : "No results"))
                                .font(.system(size: 12)).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        } else {
                            ForEach(vm.filteredMyPRs) { pr in
                                PRRowView(pr: pr, isSelected: vm.selectedPRId == pr.id) {
                                    vm.selectedPRId = pr.id
                                    vm.open(pr)
                                }
                                .id(pr.number)
                            }
                        }

                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                            .padding(.vertical, 4)

                        // Review Requested
                        PRSectionHeader(title: "Review Requested",
                                        icon: "eye.fill",
                                        count: vm.filteredReviewPRs.count,
                                        color: .orange)
                        if vm.filteredReviewPRs.isEmpty {
                            Text(vm.isLoading ? "Loading…" : (vm.searchQuery.isEmpty ? "No review requests 🎉" : "No results"))
                                .font(.system(size: 12)).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        } else {
                            ForEach(vm.filteredReviewPRs) { pr in
                                PRRowView(pr: pr, isSelected: vm.selectedPRId == pr.id) {
                                    vm.selectedPRId = pr.id
                                    vm.open(pr)
                                }
                                .id(pr.number)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                }
                .onChange(of: vm.selectedPRId) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 280, idealHeight: 420)
        .onAppear {
            navProxy.navigateUp   = { MainActor.assumeIsolated { vm.navigateUp()   } }
            navProxy.navigateDown = { MainActor.assumeIsolated { vm.navigateDown() } }
            navProxy.openSelected = { MainActor.assumeIsolated { vm.openSelected() } }
            navProxy.viewModelReady?(vm)
        }
    }

    func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Navigation Bridge

final class NavigationProxy {
    var navigateUp:    (() -> Void)?
    var navigateDown:  (() -> Void)?
    var openSelected:  (() -> Void)?
    var viewModelReady: ((PRViewModel) -> Void)?
}

// MARK: - Focus-aware Hosting View

private final class FocusableHostingView<Root: View>: NSHostingView<Root> {
    var onMoveUp:        (() -> Void)?
    var onMoveDown:      (() -> Void)?
    var onSelectCurrent: (() -> Void)?
    /// Called whenever the host window's content size changes. The surface
    /// uses this to persist the user's preferred size to UserDefaults.
    var onSizeChanged:   ((CGSize) -> Void)?
    private var eventMonitor: Any?
    private var resizeObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            installMonitor()
            installResizeObserver(on: window)
        } else {
            removeMonitor()
            removeResizeObserver()
        }
    }

    private func installMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Pass keys through when a text field is active
            if let fr = self.window?.firstResponder, fr is NSTextView { return event }
            switch event.keyCode {
            case 125: self.onMoveDown?();        return nil   // ↓
            case 126: self.onMoveUp?();          return nil   // ↑
            case 36, 76: self.onSelectCurrent?(); return nil  // Return / numpad Enter
            default: return event
            }
        }
    }

    private func removeMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        eventMonitor = nil
    }

    private func installResizeObserver(on window: NSWindow) {
        removeResizeObserver()
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.onSizeChanged?(window.contentLayoutRect.size)
        }
    }

    private func removeResizeObserver() {
        if let token = resizeObserver { NotificationCenter.default.removeObserver(token) }
        resizeObserver = nil
    }

    deinit { removeMonitor(); removeResizeObserver() }
}

// MARK: - Persisted Surface Size

/// Persists the user's preferred main-surface size across launches.
private enum GitHubPRSurfaceSize {
    static let widthKey  = "com.bttuserplugin.github.prmonitor.surfaceWidth"
    static let heightKey = "com.bttuserplugin.github.prmonitor.surfaceHeight"

    static let defaultSize = CGSize(width: 560, height: 460)
    static let minWidth:  CGFloat = 460
    static let minHeight: CGFloat = 280
    static let maxWidth:  CGFloat = 2000
    static let maxHeight: CGFloat = 1600

    static func load() -> CGSize {
        let w = UserDefaults.standard.object(forKey: widthKey)  as? CGFloat
        let h = UserDefaults.standard.object(forKey: heightKey) as? CGFloat
        guard let w, let h else { return defaultSize }
        return CGSize(
            width:  min(maxWidth,  max(minWidth,  w)),
            height: min(maxHeight, max(minHeight, h))
        )
    }

    static func save(_ size: CGSize) {
        guard size.width >= minWidth, size.height >= minHeight else { return }
        UserDefaults.standard.set(size.width,  forKey: widthKey)
        UserDefaults.standard.set(size.height, forKey: heightKey)
    }
}

// MARK: - Launcher Plugin

class GitHubPRLauncherPlugin: NSObject, BTTLauncherPluginInterface {
    weak var delegate: (any BTTLauncherPluginDelegate)?

    required override init() { super.init() }

    static func launcherPluginName()        -> String { "GitHub PRs" }
    static func launcherPluginDescription() -> String { "Browse your open GitHub PRs and review requests" }
    static func launcherPluginIcon()        -> String { "arrow.triangle.pull" }

    // Sync result – the single root entry that opens the surface.
    func launcherResults(for context: BTTLauncherPluginContext) -> [BTTLauncherPluginResult]? {
        [makeRootResult()]
    }

    func loadLauncherResults(for context: BTTLauncherPluginContext,
                             completion: @escaping ([BTTLauncherPluginResult]?) -> Void) {
        completion([makeRootResult()])
    }

    func launcherSurface(forItemIdentifier itemIdentifier: String,
                         surfaceIdentifier: String?,
                         context: BTTLauncherPluginContext) -> (any BTTLauncherPluginSurfaceInterface)? {
        guard surfaceIdentifier == "github-prs" else { return nil }
        return GitHubPRSurface()
    }

    func launcherResultSelected(_ result: BTTLauncherPluginResult,
                                context: BTTLauncherPluginContext) {
        // No-op; surface handles its own actions.
    }

    private func makeRootResult() -> BTTLauncherPluginResult {
        let r = BTTLauncherPluginResult()
        r.itemIdentifier    = "github-prs-root"
        r.title             = "GitHub PRs"
        r.subtitle          = "Adobe-CreativeCloud / photoshop"
        r.systemImageName   = "arrow.triangle.pull"
        r.surfaceIdentifier = "github-prs"
        r.trailingHint      = "Open"
        return r
    }
}

// MARK: - Surface

final class GitHubPRSurface: NSObject, BTTLauncherPluginSurfaceInterface {
    weak var delegate: (any BTTLauncherPluginSurfaceDelegate)?

    private var vm: PRViewModel?

    func makeLauncherSurfaceView() -> NSView {
        let navProxy = NavigationProxy()
        let view = PRDashboard(navProxy: navProxy)
        let hosting = FocusableHostingView(rootView: view)
        hosting.onMoveUp        = { navProxy.navigateUp?() }
        hosting.onMoveDown      = { navProxy.navigateDown?() }
        hosting.onSelectCurrent = { navProxy.openSelected?() }
        hosting.onSizeChanged   = { size in GitHubPRSurfaceSize.save(size) }
        // Stash the VM so we can forward the launcher's search query into it.
        navProxy.viewModelReady = { [weak self] vm in self?.vm = vm }
        return hosting
    }

    func launcherSurfacePreferredContentSize() -> CGSize { GitHubPRSurfaceSize.load() }
    func launcherSurfaceKeepsLauncherPinned()  -> Bool   { true }
    func launcherSurfacePlaceholderText()      -> String? { "Filter PRs…" }
    func launcherSurfaceFooterHint()           -> String? { "↑/↓ Navigate  ·  Return Open  ·  Esc Back" }

    func launcherSurfaceShouldBypassGlobalKeyboardHandling(for event: NSEvent) -> Bool { true }

    func launcherSurfaceQueryDidChange(_ query: String?) {
        let q = query ?? ""
        DispatchQueue.main.async { [weak self] in
            self?.vm?.searchQuery = q
        }
    }
}
