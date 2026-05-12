// BTT-Plugin-Name: Stock Prices
// BTT-Plugin-Identifier: com.bttuserplugin.stockprices
// BTT-Plugin-Type: Launcher
// BTT-Plugin-Icon: chart.line.uptrend.xyaxis
// BTT-AI-Managed: true

import AppKit
import SwiftUI

// MARK: - Model

struct StockQuote {
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let timestamp: Date
    let historicalPrices: [Double]   // last ~5 trading days of closes

    var isPositive: Bool { change >= 0 }
    var priceString: String { String(format: "$%.2f", price) }
    var changeString: String {
        let sign = isPositive ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change))  (\(sign)\(String(format: "%.2f", changePercent))%)"
    }
}

// MARK: - Plugin

class StockPricesPlugin: NSObject, BTTLauncherPluginInterface {
    weak var delegate: (any BTTLauncherPluginDelegate)?

    private var cachedQuotes: [String: StockQuote] = [:]
    private var isLoading = false
    private var lastFetch: Date?
    private let cacheTTL: TimeInterval = 60
    private let watchlist: [String] = ["ADBE","AAPL", "GOOGL", "MSFT", "AMZN", "NVDA", "TSLA", "META"]

    static func launcherPluginName() -> String { "Stock Prices" }
    static func launcherPluginDescription() -> String { "Live stock prices. Type a ticker to look it up." }
    static func launcherPluginIcon() -> String { "chart.line.uptrend.xyaxis" }

    func launcherResults(for context: BTTLauncherPluginContext) -> [BTTLauncherPluginResult]? {
        let query = (context.query ?? "").uppercased().trimmingCharacters(in: .whitespaces)

        let needsRefresh = lastFetch == nil || Date().timeIntervalSince(lastFetch!) > cacheTTL
        if needsRefresh && !isLoading {
            refreshAll()
        }

        var symbols = watchlist
        if !query.isEmpty {
            symbols = watchlist.filter { $0.hasPrefix(query) }
        }

        var results: [BTTLauncherPluginResult] = []

        for symbol in symbols {
            let r = BTTLauncherPluginResult()
            r.itemIdentifier = "stock-\(symbol)"
            r.keywords = [symbol]

            if let q = cachedQuotes[symbol] {
                r.title = "\(symbol)   \(q.priceString)"
                r.subtitle = "\(q.name)  ·  \(q.changeString)"
                r.systemImageName = q.isPositive
                    ? "arrow.up.right.circle.fill"
                    : "arrow.down.left.circle.fill"
                r.surfaceIdentifier = "detail-\(symbol)"
                r.trailingHint = q.isPositive ? "▲" : "▼"
            } else {
                r.title = symbol
                r.subtitle = isLoading ? "Fetching price…" : "Price unavailable – tap Refresh"
                r.systemImageName = "chart.bar.fill"
                r.trailingHint = ""
            }

            let refreshCmd = BTTLauncherPluginCommand()
            refreshCmd.commandIdentifier = "cmd-refresh"
            refreshCmd.title = "Refresh All"
            refreshCmd.systemImageName = "arrow.clockwise"
            let sc = BTTLauncherPluginShortcut()
            sc.character = "r"
            sc.modifierFlags = [.command]
            sc.displayKeys = ["⌘", "R"]
            refreshCmd.shortcut = sc
            refreshCmd.closesLauncherOnSuccess = false
            r.commands = [refreshCmd]

            results.append(r)
        }

        // Footer refresh row
        let refreshRow = BTTLauncherPluginResult()
        refreshRow.itemIdentifier = "action-refresh-all"
        refreshRow.title = isLoading ? "Refreshing prices…" : "Refresh All Prices"
        if let lf = lastFetch {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            refreshRow.subtitle = "Last updated: \(fmt.string(from: lf))"
        } else {
            refreshRow.subtitle = "Prices not yet loaded"
        }
        refreshRow.systemImageName = isLoading ? "hourglass" : "arrow.clockwise.circle.fill"
        refreshRow.primaryActionIdentifier = "action-refresh-all"
        refreshRow.trailingHint = "↩"
        results.append(refreshRow)

        return results
    }

    func performAction(
        forItemIdentifier itemIdentifier: String,
        actionIdentifier: String?,
        context: BTTLauncherPluginContext
    ) -> BTTLauncherPluginActionResult? {
        let ar = BTTLauncherPluginActionResult()
        ar.closeLauncher = false

        let isRefresh = itemIdentifier == "action-refresh-all"
            || actionIdentifier == "action-refresh-all"
            || actionIdentifier == "cmd-refresh"

        if isRefresh {
            refreshAll()
            ar.success = true
            ar.message = "Refreshing stock prices…"
        } else {
            ar.success = true
        }
        return ar
    }

    func launcherSurface(
        forItemIdentifier itemIdentifier: String,
        surfaceIdentifier: String?,
        context: BTTLauncherPluginContext
    ) -> (any BTTLauncherPluginSurfaceInterface)? {
        let symbol = itemIdentifier.replacingOccurrences(of: "stock-", with: "")
        guard let q = cachedQuotes[symbol] else { return nil }
        return StockDetailSurface(quote: q)
    }

    // MARK: - Fetch

    private func refreshAll() {
        guard !isLoading else { return }
        isLoading = true
        delegate?.requestLauncherResultsRefresh()

        let symbols = watchlist
        let group = DispatchGroup()
        var fetched: [String: StockQuote] = [:]
        let lock = NSLock()

        for symbol in symbols {
            group.enter()
            fetchQuote(symbol: symbol) { q in
                if let q = q {
                    lock.lock(); fetched[symbol] = q; lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            for (sym, q) in fetched { self.cachedQuotes[sym] = q }
            self.lastFetch = Date()
            self.isLoading = false
            self.delegate?.requestLauncherResultsRefresh()
        }
    }

    private func fetchQuote(symbol: String, completion: @escaping (StockQuote?) -> Void) {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        // Use 5d range with daily interval to get historical closes for the sparkline
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1h&range=5d"
        guard let url = URL(string: urlStr) else { completion(nil); return }

        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data, error == nil else { completion(nil); return }
            do {
                guard
                    let json  = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let chart = json["chart"] as? [String: Any],
                    let arr   = chart["result"] as? [[String: Any]],
                    let first = arr.first,
                    let meta  = first["meta"] as? [String: Any]
                else { completion(nil); return }

                let price     = meta["regularMarketPrice"] as? Double ?? 0
                let prevClose = meta["chartPreviousClose"]  as? Double ?? price
                let name      = (meta["longName"]  as? String)
                             ?? (meta["shortName"] as? String)
                             ?? symbol
                let change    = price - prevClose
                let pct       = prevClose != 0 ? (change / prevClose) * 100 : 0

                // Extract historical closing prices (NSNull entries = market-closed days, filtered out)
                var historicalPrices: [Double] = []
                if let indicators = first["indicators"] as? [String: Any],
                   let quoteArr = indicators["quote"] as? [[String: Any]],
                   let q = quoteArr.first,
                   let closes = q["close"] as? [Any] {
                    historicalPrices = closes.compactMap { $0 as? Double }
                }
                // Replace last data point with the live price for accuracy
                if !historicalPrices.isEmpty {
                    historicalPrices[historicalPrices.count - 1] = price
                } else {
                    historicalPrices = [prevClose, price]
                }

                completion(StockQuote(
                    symbol: symbol, name: name,
                    price: price, change: change,
                    changePercent: pct, timestamp: Date(),
                    historicalPrices: historicalPrices
                ))
            } catch { completion(nil) }
        }.resume()
    }
}

// MARK: - Chart Range

enum StockRange: String, CaseIterable, Equatable {
    case oneDay     = "1D"
    case fiveDay    = "5D"
    case oneMonth   = "1M"
    case threeMonth = "3M"
    case sixMonth   = "6M"
    case oneYear    = "1Y"
    case fiveYear   = "5Y"

    var rangeParam: String {
        switch self {
        case .oneDay:     return "1d"
        case .fiveDay:    return "5d"
        case .oneMonth:   return "1mo"
        case .threeMonth: return "3mo"
        case .sixMonth:   return "6mo"
        case .oneYear:    return "1y"
        case .fiveYear:   return "5y"
        }
    }

    /// Yahoo Finance interval — balances density vs. response size.
    var intervalParam: String {
        switch self {
        case .oneDay:     return "5m"   // ~78 pts  (5-min bars, 1 trading day)
        case .fiveDay:    return "1h"   // ~33 pts  (hourly, 5 trading days)
        case .oneMonth:   return "1d"   // ~21 pts
        case .threeMonth: return "1d"   // ~63 pts
        case .sixMonth:   return "1d"   // ~126 pts
        case .oneYear:    return "1d"   // ~252 pts
        case .fiveYear:   return "1wk"  // ~260 pts (weekly)
        }
    }

    var startLabel: String {
        switch self {
        case .oneDay:     return "Today"
        case .fiveDay:    return "5D ago"
        case .oneMonth:   return "1M ago"
        case .threeMonth: return "3M ago"
        case .sixMonth:   return "6M ago"
        case .oneYear:    return "1Y ago"
        case .fiveYear:   return "5Y ago"
        }
    }
}

// MARK: - Detail Surface

final class StockDetailSurface: NSObject, BTTLauncherPluginSurfaceInterface {
    weak var delegate: (any BTTLauncherPluginSurfaceDelegate)?
    private let quote: StockQuote

    init(quote: StockQuote) { self.quote = quote }

    func makeLauncherSurfaceView() -> NSView {
        NSHostingView(rootView: StockDetailView(quote: quote))
    }

    func launcherSurfacePreferredContentSize() -> CGSize { CGSize(width: 560, height: 375) }
    func launcherSurfaceKeepsLauncherPinned() -> Bool { true }
    func launcherSurfaceFooterHint() -> String? { "Press Esc to go back" }

    func launcherSurfaceStatusText() -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm:ss a"
        return "Updated \(fmt.string(from: quote.timestamp))"
    }
}

// MARK: - Sparkline Chart

struct SparklineView: View {
    let prices: [Double]
    let isPositive: Bool

    @State private var hoverIndex: Int? = nil

    private var lineColor: Color { isPositive ? Color.green : Color(red: 1.0, green: 0.3, blue: 0.3) }

    /// Compute the canvas-space point for data index `i` given view dimensions.
    private func makePoint(_ i: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        let n      = prices.count
        let minP   = prices.min()!
        let maxP   = prices.max()!
        let range  = (maxP - minP) == 0 ? 1.0 : (maxP - minP)
        let pad: CGFloat = 6
        let x = pad + (width  - pad * 2) * CGFloat(i) / CGFloat(n - 1)
        let y = (height - pad) - (height - pad * 2) * CGFloat((prices[i] - minP) / range)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack(alignment: .topLeading) {

                // ── Sparkline canvas (also draws the hover indicator) ──
                Canvas { ctx, size in
                    guard prices.count >= 2 else { return }

                    let minP  = prices.min()!
                    let maxP  = prices.max()!
                    let range = (maxP - minP) == 0 ? 1.0 : (maxP - minP)
                    let n     = prices.count
                    let pad: CGFloat = 6

                    func point(_ i: Int) -> CGPoint {
                        let x = pad + (size.width  - pad * 2) * CGFloat(i) / CGFloat(n - 1)
                        let y = (size.height - pad) - (size.height - pad * 2)
                              * CGFloat((prices[i] - minP) / range)
                        return CGPoint(x: x, y: y)
                    }

                    // Build smooth bezier line
                    var linePath = Path()
                    linePath.move(to: point(0))
                    for i in 1..<n {
                        let prev = point(i - 1)
                        let curr = point(i)
                        let cp1 = CGPoint(x: (prev.x + curr.x) / 2, y: prev.y)
                        let cp2 = CGPoint(x: (prev.x + curr.x) / 2, y: curr.y)
                        linePath.addCurve(to: curr, control1: cp1, control2: cp2)
                    }

                    // Gradient fill under line
                    var fillPath = linePath
                    let lastPt  = point(n - 1)
                    let firstPt = point(0)
                    fillPath.addLine(to: CGPoint(x: lastPt.x,  y: size.height))
                    fillPath.addLine(to: CGPoint(x: firstPt.x, y: size.height))
                    fillPath.closeSubpath()

                    let fillColor = isPositive
                        ? Color.green.opacity(0.12)
                        : Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.12)
                    ctx.fill(fillPath, with: .color(fillColor))

                    // Stroke the line
                    ctx.stroke(
                        linePath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )

                    // Glowing dot at last (current) price point
                    let last     = point(n - 1)
                    let outerRect = CGRect(x: last.x - 6,   y: last.y - 6,   width: 12, height: 12)
                    let innerRect = CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7,  height: 7)
                    ctx.fill(Path(ellipseIn: outerRect), with: .color(lineColor.opacity(0.25)))
                    ctx.fill(Path(ellipseIn: innerRect),  with: .color(lineColor))

                    // ── Hover: dashed crosshair + snapped dot ────────────
                    if let idx = hoverIndex, prices.indices.contains(idx) {
                        let pt = point(idx)

                        // Vertical dashed crosshair
                        var crosshair = Path()
                        crosshair.move(to: CGPoint(x: pt.x, y: 0))
                        crosshair.addLine(to: CGPoint(x: pt.x, y: size.height))
                        ctx.stroke(crosshair, with: .color(lineColor.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                        // Dot at hovered data point
                        let dotOuter = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                        let dotInner = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6,  height: 6)
                        ctx.fill(Path(ellipseIn: dotOuter), with: .color(lineColor.opacity(0.3)))
                        ctx.fill(Path(ellipseIn: dotInner), with: .color(lineColor))
                    }
                }

                // ── Floating price label ─────────────────────────────────
                if let idx = hoverIndex, prices.indices.contains(idx) {
                    let pt     = makePoint(idx, width: w, height: h)
                    let labelX = min(max(pt.x, 30), w - 30)
                    let labelY = max(pt.y - 22, 14)

                    Text(String(format: "$%.2f", prices[idx]))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 1)
                        )
                        .fixedSize()
                        .position(x: labelX, y: labelY)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    guard prices.count >= 2 else { break }
                    let pad: CGFloat = 6
                    let rawIdx = (loc.x - pad) / (w - pad * 2) * CGFloat(prices.count - 1)
                    hoverIndex = max(0, min(prices.count - 1, Int(rawIdx.rounded())))
                case .ended:
                    hoverIndex = nil
                }
            }
        }
    }
}

// MARK: - Detail View

struct StockDetailView: View {
    let quote: StockQuote

    @State private var selectedRange: StockRange = .oneDay
    @State private var chartPrices:   [Double]
    @State private var isFetchingChart = true

    init(quote: StockQuote) {
        self.quote = quote
        self._chartPrices = State(initialValue: [])
    }

    private var accentColor: Color {
        quote.isPositive ? .green : Color(red: 1.0, green: 0.3, blue: 0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.symbol)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(quote.name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(quote.priceString)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    // Pill badge
                    HStack(spacing: 3) {
                        Image(systemName: quote.isPositive ? "arrow.up.right" : "arrow.down.left")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%+.2f  (%+.2f%%)", quote.change, quote.changePercent))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.13))
                    .clipShape(Capsule())
                }
            }
            .padding(.bottom, 14)

            // ── Sparkline ────────────────────────────────────────────
            ZStack {
                if chartPrices.count >= 2 {
                    SparklineView(prices: chartPrices, isPositive: quote.isPositive)
                        .opacity(isFetchingChart ? 0.4 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: isFetchingChart)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .frame(height: 110)
            .padding(.bottom, 6)

            // ── Range Selector + axis labels ─────────────────────────
            HStack(spacing: 2) {
                ForEach(StockRange.allCases, id: \.self) { range in
                    Button(action: { selectedRange = range }) {
                        Text(range.rawValue)
                            .font(.system(size: 11,
                                          weight: selectedRange == range ? .semibold : .regular))
                            .foregroundColor(selectedRange == range ? accentColor : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedRange == range
                                          ? accentColor.opacity(0.12)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(selectedRange.startLabel)
                    .font(.system(size: 9))
                    .foregroundColor(Color.secondary.opacity(0.6))
                Text("→ Now")
                    .font(.system(size: 9))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .padding(.bottom, 14)

            Divider()
                .padding(.bottom, 12)

            // ── Stats row ────────────────────────────────────────────
            HStack(spacing: 0) {
                StatTile(label: "Change",    value: String(format: "%+.2f",   quote.change),        isAccent: true, pos: quote.isPositive)
                Spacer()
                StatTile(label: "Change %",  value: String(format: "%+.2f%%", quote.changePercent), isAccent: true, pos: quote.isPositive)
                Spacer()
                StatTile(label: "Prev Close", value: String(format: "$%.2f", quote.price - quote.change), isAccent: false, pos: true)
                Spacer()
                StatTile(label: "Price",     value: quote.priceString,                               isAccent: false, pos: true)
            }
        }
        .padding(20)
        // fires immediately on appear, and again whenever selectedRange changes;
        // automatically cancels in-flight request if the user switches range quickly
        .task(id: selectedRange) {
            await fetchChart(for: selectedRange)
        }
    }

    // MARK: - Chart Fetch

    private func fetchChart(for range: StockRange) async {
        await MainActor.run { isFetchingChart = true }

        let symbol  = quote.symbol
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let urlStr  = "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)"
                    + "?interval=\(range.intervalParam)&range=\(range.rangeParam)"
        guard let url = URL(string: urlStr) else {
            await MainActor.run { isFetchingChart = false }
            return
        }

        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            var prices: [Double] = []
            if let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart  = json["chart"]        as? [String: Any],
               let arr    = chart["result"]       as? [[String: Any]],
               let first  = arr.first,
               let indic  = first["indicators"]  as? [String: Any],
               let qArr   = indic["quote"]        as? [[String: Any]],
               let q      = qArr.first,
               let closes = q["close"]            as? [Any] {
                prices = closes.compactMap { $0 as? Double }
            }
            await MainActor.run {
                if !prices.isEmpty { chartPrices = prices }
                isFetchingChart = false
            }
        } catch {
            await MainActor.run { isFetchingChart = false }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let isAccent: Bool
    let pos: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 14, design: .rounded).weight(.semibold))
                .foregroundColor(isAccent ? (pos ? .green : Color(red: 1.0, green: 0.3, blue: 0.3)) : .primary)
        }
    }
}
