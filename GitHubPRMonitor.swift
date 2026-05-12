// BTT-Plugin-Name: GitHub PR Monitor
// BTT-Plugin-Type: FloatingMenuWidget
// BTT-Plugin-Icon: arrow.triangle.pull
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

    func open(_ pr: GitHubPR) {
        guard let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - PR Row

struct PRRowView: View {
    let pr: GitHubPR
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
                    .foregroundColor(hovered ? .accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(hovered ? Color.accentColor.opacity(0.12) : Color.clear)
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
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {

                    // My Open PRs
                    PRSectionHeader(title: "My Open PRs",
                                    icon: "person.fill",
                                    count: vm.myPRs.count,
                                    color: .blue)
                    if vm.myPRs.isEmpty {
                        Text(vm.isLoading ? "Loading…" : "No open PRs 🎉")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    } else {
                        ForEach(vm.myPRs) { pr in
                            PRRowView(pr: pr) { vm.open(pr) }
                        }
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                        .padding(.vertical, 4)

                    // Review Requested
                    PRSectionHeader(title: "Review Requested",
                                    icon: "eye.fill",
                                    count: vm.reviewPRs.count,
                                    color: .orange)
                    if vm.reviewPRs.isEmpty {
                        Text(vm.isLoading ? "Loading…" : "No review requests 🎉")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    } else {
                        ForEach(vm.reviewPRs) { pr in
                            PRRowView(pr: pr) { vm.open(pr) }
                        }
                    }

                    Spacer(minLength: 8)
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 280, idealHeight: 420)
    }

    func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Widget Class

class GitHubPRWidget: NSObject, BTTFloatingMenuWidgetInterface {
    weak var delegate: (any BTTFloatingMenuWidgetDelegate)?

    static func widgetName() -> String        { "GitHub PR Monitor" }
    static func widgetDescription() -> String { "Lists your open PRs and review requests in Adobe-CreativeCloud/photoshop" }
    static func widgetIcon() -> String        { "arrow.triangle.pull" }
    static func widgetWantsInteractiveView() -> Bool { true }

    static func widgetMinWidth() -> CGFloat   { 460 }
    static func widgetMinHeight() -> CGFloat  { 280 }
    static func widgetMaxWidth() -> CGFloat   { 700 }
    static func widgetMaxHeight() -> CGFloat  { 700 }

    func makeWidgetView() -> NSView {
        NSHostingView(rootView: PRDashboard())
    }
}
