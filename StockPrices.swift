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

/// Persists the user's preferred detail-surface size across launches.
private enum StockSurfaceSize {
    static let widthKey  = "com.bttuserplugin.stocks.surfaceWidth"
    static let heightKey = "com.bttuserplugin.stocks.surfaceHeight"

    static let defaultSize = CGSize(width: 560, height: 375)
    static let minWidth:  CGFloat = 420
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

/// `NSHostingView` subclass that reports host-window size changes so the
/// surface can persist the user's resized dimensions.
private final class ResizableHostingView<Root: View>: NSHostingView<Root> {
    var onSizeChanged: ((CGSize) -> Void)?
    private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            installResizeObserver(on: window)
        } else {
            removeResizeObserver()
        }
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

    deinit { removeResizeObserver() }
}

final class StockDetailSurface: NSObject, BTTLauncherPluginSurfaceInterface {
    weak var delegate: (any BTTLauncherPluginSurfaceDelegate)?
    private let quote: StockQuote

    init(quote: StockQuote) { self.quote = quote }

    func makeLauncherSurfaceView() -> NSView {
        let view = ResizableHostingView(rootView: StockDetailView(quote: quote))
        view.onSizeChanged = { size in StockSurfaceSize.save(size) }
        return view
    }

    func launcherSurfacePreferredContentSize() -> CGSize { StockSurfaceSize.load() }
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
    /// Optional values — trailing `nil`s mean "no data yet" (e.g. intraday
    /// 1D chart during a live trading session) and reserve x-axis space
    /// without drawing a line over them.
    let prices: [Double?]
    let isPositive: Bool
    /// When set, draws hour labels along the bottom of the chart at evenly
    /// spaced positions between `start` and `end` (e.g. for the 1D range).
    var timeAxis: (start: Date, end: Date)? = nil

    @State private var hoverIndex: Int? = nil

    private var lineColor: Color { isPositive ? Color.green : Color(red: 1.0, green: 0.3, blue: 0.3) }

    private var validValues: [Double] { prices.compactMap { $0 } }
    private var firstValidIndex: Int? { prices.firstIndex(where: { $0 != nil }) }
    private var lastValidIndex:  Int? { prices.lastIndex(where:  { $0 != nil }) }

    /// Compute the canvas-space point for data index `i` given view dimensions.
    private func makePoint(_ i: Int, width: CGFloat, height: CGFloat) -> CGPoint? {
        guard let v = prices[i] else { return nil }
        let vals  = validValues
        guard let minP = vals.min(), let maxP = vals.max() else { return nil }
        let range = (maxP - minP) == 0 ? 1.0 : (maxP - minP)
        let n     = prices.count
        let pad: CGFloat = 6
        let x = pad + (width  - pad * 2) * CGFloat(i) / CGFloat(max(n - 1, 1))
        let y = (height - pad) - (height - pad * 2) * CGFloat((v - minP) / range)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack(alignment: .topLeading) {

                // ── Sparkline canvas (also draws the hover indicator) ──
                Canvas { ctx, size in
                    let vals = validValues
                    guard vals.count >= 2,
                          let firstIdx = firstValidIndex,
                          let lastIdx  = lastValidIndex
                    else { return }

                    let minP  = vals.min()!
                    let maxP  = vals.max()!
                    let range = (maxP - minP) == 0 ? 1.0 : (maxP - minP)
                    let n     = prices.count
                    let pad: CGFloat = 6

                    func point(_ i: Int) -> CGPoint? {
                        guard let v = prices[i] else { return nil }
                        let x = pad + (size.width  - pad * 2) * CGFloat(i) / CGFloat(max(n - 1, 1))
                        let y = (size.height - pad) - (size.height - pad * 2)
                              * CGFloat((v - minP) / range)
                        return CGPoint(x: x, y: y)
                    }

                    // Collect only the valid points in [firstIdx...lastIdx].
                    // Interior nils are skipped (curve bridges over them)
                    // — only trailing nils (past lastIdx) represent
                    // "no data yet" for an in-progress trading session.
                    let validPts: [CGPoint] = (firstIdx...lastIdx).compactMap { point($0) }
                    guard validPts.count >= 2,
                          let firstPt = validPts.first,
                          let lastPt  = validPts.last
                    else { return }

                    // Smooth bezier curve through valid points
                    func curve(through pts: [CGPoint], appendingTo path: inout Path) {
                        path.move(to: pts[0])
                        for i in 1..<pts.count {
                            let prev = pts[i - 1]
                            let curr = pts[i]
                            let cp1  = CGPoint(x: (prev.x + curr.x) / 2, y: prev.y)
                            let cp2  = CGPoint(x: (prev.x + curr.x) / 2, y: curr.y)
                            path.addCurve(to: curr, control1: cp1, control2: cp2)
                        }
                    }

                    var linePath = Path()
                    curve(through: validPts, appendingTo: &linePath)

                    // Gradient fill: bottom-left → up → curve → down → close
                    var fillPath = Path()
                    fillPath.move(to: CGPoint(x: firstPt.x, y: size.height))
                    fillPath.addLine(to: firstPt)
                    for i in 1..<validPts.count {
                        let prev = validPts[i - 1]
                        let curr = validPts[i]
                        let cp1  = CGPoint(x: (prev.x + curr.x) / 2, y: prev.y)
                        let cp2  = CGPoint(x: (prev.x + curr.x) / 2, y: curr.y)
                        fillPath.addCurve(to: curr, control1: cp1, control2: cp2)
                    }
                    fillPath.addLine(to: CGPoint(x: lastPt.x, y: size.height))
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

                    // Glowing dot at last (current) valid price point
                    let last = lastPt
                    let outerRect = CGRect(x: last.x - 6,   y: last.y - 6,   width: 12, height: 12)
                    let innerRect = CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7,  height: 7)
                    ctx.fill(Path(ellipseIn: outerRect), with: .color(lineColor.opacity(0.25)))
                    ctx.fill(Path(ellipseIn: innerRect),  with: .color(lineColor))

                    // ── Hover: dashed crosshair + snapped dot ────────────
                    if let idx = hoverIndex,
                       prices.indices.contains(idx),
                       let pt = point(idx) {

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
                if let idx = hoverIndex,
                   prices.indices.contains(idx),
                   let v  = prices[idx],
                   let pt = makePoint(idx, width: w, height: h) {
                    let labelX = min(max(pt.x, 30), w - 30)
                    let labelY = max(pt.y - 22, 14)

                    Text(String(format: "$%.2f", v))
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
                    guard prices.count >= 2,
                          let firstIdx = firstValidIndex,
                          let lastIdx  = lastValidIndex
                    else { break }
                    let pad: CGFloat = 6
                    let rawIdx = (loc.x - pad) / (w - pad * 2) * CGFloat(prices.count - 1)
                    let clamped = max(firstIdx, min(lastIdx, Int(rawIdx.rounded())))
                    // snap to nearest valid index (skip any nil gaps)
                    hoverIndex = prices[clamped] != nil ? clamped : lastIdx
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
    @State private var chartPrices:   [Double?]
    @State private var chartTimestamps: [Date] = []
    @State private var isFetchingChart = true
    @State private var tradingStart: Date? = nil
    @State private var tradingEnd:   Date? = nil

    init(quote: StockQuote) {
        self.quote = quote
        self._chartPrices = State(initialValue: [])
    }

    // ── Range-aware change ────────────────────────────────────────
    // Change/Change% are computed against the first point of the currently
    // selected range so they reflect what the chart is showing.
    // Prev Close is intentionally NOT range-aware — it always reports the
    // previous trading day's close from the initial quote fetch.
    private var validChartPrices: [Double] { chartPrices.compactMap { $0 } }
    private var rangeBaseline: Double? {
        validChartPrices.count >= 2 ? validChartPrices.first : nil
    }
    private var rangeChange: Double {
        guard let base = rangeBaseline else { return quote.change }
        return quote.price - base
    }
    private var rangeChangePercent: Double {
        guard let base = rangeBaseline, base != 0 else { return quote.changePercent }
        return (rangeChange / base) * 100
    }
    private var rangeIsPositive: Bool { rangeChange >= 0 }
    private var prevTradingDayClose: Double { quote.price - quote.change }

    /// X-axis tick labels for the current chart range.
    /// Returns x-fractions in `[0, 1]` aligned with the sparkline's coordinate
    /// system, plus a human label (e.g. "10 am", "7 May", "Feb 2026").
    private var axisLabels: [(x: CGFloat, text: String)] {
        switch selectedRange {
        case .oneDay:
            // Hour ticks across the regular trading session.
            guard let start = tradingStart, let end = tradingEnd, end > start
            else { return [] }
            let total = end.timeIntervalSince(start)
            let cal   = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day, .hour], from: start)
            comps.hour = (comps.hour ?? 0) + 1
            comps.minute = 0; comps.second = 0
            guard var tick = cal.date(from: comps) else { return [] }
            let fmt = DateFormatter(); fmt.dateFormat = "h a"
            var out: [(CGFloat, String)] = []
            while tick < end {
                let frac = CGFloat(tick.timeIntervalSince(start) / total)
                out.append((frac, fmt.string(from: tick).lowercased()))
                tick = cal.date(byAdding: .hour, value: 1, to: tick) ?? end
            }
            return out

        case .fiveDay, .oneMonth, .threeMonth:
            // Date ticks ("7 May", "16 Apr", "24 Apr", …)
            return dateTicks(format: "d MMM", targetCount: selectedRange == .fiveDay ? 4 : 4)

        case .sixMonth, .oneYear:
            // Month ticks ("Feb 2026")
            return monthTicks(format: "MMM yyyy", targetCount: selectedRange == .sixMonth ? 1 : 3)

        case .fiveYear:
            // Year ticks ("2026")
            return monthTicks(format: "yyyy", targetCount: 4)
        }
    }

    /// Pick roughly `targetCount` evenly spaced data points (skipping nils)
    /// and turn them into x-fraction + formatted-date pairs.
    private func dateTicks(format: String, targetCount: Int) -> [(CGFloat, String)] {
        guard chartTimestamps.count == chartPrices.count,
              chartTimestamps.count >= 2
        else { return [] }
        let validIdx = chartPrices.indices.filter { chartPrices[$0] != nil }
        guard validIdx.count >= 2 else { return [] }

        let fmt = DateFormatter(); fmt.dateFormat = format
        let n   = chartTimestamps.count
        let step = max(1, validIdx.count / targetCount)
        var picked: [Int] = []
        var i = validIdx.first!
        while i <= validIdx.last! {
            if chartPrices[i] != nil { picked.append(i) }
            i += step
        }
        return picked.map { idx in
            (CGFloat(idx) / CGFloat(max(n - 1, 1)),
             fmt.string(from: chartTimestamps[idx]))
        }
    }

    /// Like `dateTicks` but snaps to month-start positions so labels read
    /// e.g. "Feb 2026", "May 2026".
    private func monthTicks(format: String, targetCount: Int) -> [(CGFloat, String)] {
        guard chartTimestamps.count == chartPrices.count,
              chartTimestamps.count >= 2
        else { return [] }
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = format
        let n = chartTimestamps.count

        // Group indices by month-start (or year-start for 5Y) and pick the
        // first index of each group.
        var seen = Set<String>()
        var firstOfGroup: [Int] = []
        for i in 0..<n {
            let date = chartTimestamps[i]
            let key: String
            if format.contains("MMM") {
                let c = cal.dateComponents([.year, .month], from: date)
                key = "\(c.year ?? 0)-\(c.month ?? 0)"
            } else {
                key = "\(cal.component(.year, from: date))"
            }
            if !seen.contains(key) {
                seen.insert(key)
                firstOfGroup.append(i)
            }
        }
        // Drop the very first group if it's right at the start (avoids a label
        // squished against the left edge), and downsample to ~targetCount.
        if firstOfGroup.count > targetCount + 1 {
            let stride = max(1, firstOfGroup.count / targetCount)
            firstOfGroup = firstOfGroup.enumerated()
                .compactMap { (off, idx) in off % stride == 0 ? idx : nil }
        }
        return firstOfGroup.map { idx in
            (CGFloat(idx) / CGFloat(max(n - 1, 1)),
             fmt.string(from: chartTimestamps[idx]))
        }
    }

    private var accentColor: Color {
        rangeIsPositive ? .green : Color(red: 1.0, green: 0.3, blue: 0.3)
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
                        Image(systemName: rangeIsPositive ? "arrow.up.right" : "arrow.down.left")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%+.2f  (%+.2f%%)", rangeChange, rangeChangePercent))
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

            // ── Range Selector (above chart) ─────────────────────────
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
            }
            .padding(.bottom, 8)

            // ── Sparkline + x-axis labels ────────────────────────────
            VStack(spacing: 0) {
                ZStack {
                    if validChartPrices.count >= 2 {
                        SparklineView(prices: chartPrices, isPositive: rangeIsPositive)
                            .opacity(isFetchingChart ? 0.4 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: isFetchingChart)
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .frame(height: 110)

                // Reserve the axis row unconditionally so range changes
                // don't cause a layout shift (= visible UI flicker).
                GeometryReader { proxy in
                    let pad: CGFloat = 6
                    ForEach(Array(axisLabels.enumerated()), id: \.offset) { _, item in
                        let x = pad + (proxy.size.width - pad * 2) * item.x
                        Text(item.text)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(Color.secondary.opacity(0.7))
                            .fixedSize()
                            .position(x: x, y: 8)
                    }
                }
                .frame(height: 16)
            }
            .padding(.bottom, 14)

            Divider()
                .padding(.bottom, 12)

            // ── Stats row ────────────────────────────────────────────
            HStack(spacing: 0) {
                StatTile(label: "Change",    value: String(format: "%+.2f",   rangeChange),        isAccent: true, pos: rangeIsPositive)
                Spacer()
                StatTile(label: "Change %",  value: String(format: "%+.2f%%", rangeChangePercent), isAccent: true, pos: rangeIsPositive)
                Spacer()
                StatTile(label: "Prev Close", value: String(format: "$%.2f", prevTradingDayClose), isAccent: false, pos: true)
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
            var prices: [Double?] = []
            var tradingDayStart: TimeInterval? = nil
            var tradingDayEnd:   TimeInterval? = nil
            var timestamps: [TimeInterval] = []
            if let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart  = json["chart"]        as? [String: Any],
               let arr    = chart["result"]       as? [[String: Any]],
               let first  = arr.first,
               let indic  = first["indicators"]  as? [String: Any],
               let qArr   = indic["quote"]        as? [[String: Any]],
               let q      = qArr.first,
               let closes = q["close"]            as? [Any] {
                // Preserve trailing NSNull entries — they reserve x-axis space
                // for the remainder of an in-progress 1D trading session.
                prices = closes.map { $0 as? Double }
                if let ts = first["timestamp"] as? [Any] {
                    timestamps = ts.compactMap {
                        if let i = $0 as? Int    { return TimeInterval(i) }
                        if let d = $0 as? Double { return d }
                        return nil
                    }
                }
                if let meta = first["meta"] as? [String: Any],
                   let period = (meta["currentTradingPeriod"] as? [String: Any])?["regular"]
                              as? [String: Any] {
                    if let s = period["start"] as? Int    { tradingDayStart = TimeInterval(s) }
                    if let s = period["start"] as? Double { tradingDayStart = s }
                    if let e = period["end"]   as? Int    { tradingDayEnd   = TimeInterval(e) }
                    if let e = period["end"]   as? Double { tradingDayEnd   = e }
                }
            }

            // ── 1D padding: Yahoo only returns bars up to "now" during a
            // live trading session. Pad with trailing nils so the x-axis
            // spans the full regular trading day (matches Google Finance).
            if range == .oneDay,
               let start = tradingDayStart,
               let end   = tradingDayEnd,
               end > start,
               !prices.isEmpty,
               timestamps.count == prices.count {
                let interval: TimeInterval = 5 * 60  // matches intervalParam "5m"
                let totalSlots = max(prices.count,
                                     Int(((end - start) / interval).rounded(.up)))
                if totalSlots > prices.count {
                    prices.append(contentsOf:
                        Array<Double?>(repeating: nil, count: totalSlots - prices.count))
                }
            }

            await MainActor.run {
                if prices.contains(where: { $0 != nil }) { chartPrices = prices }
                chartTimestamps = timestamps.map { Date(timeIntervalSince1970: $0) }
                if range == .oneDay, let s = tradingDayStart, let e = tradingDayEnd {
                    tradingStart = Date(timeIntervalSince1970: s)
                    tradingEnd   = Date(timeIntervalSince1970: e)
                } else {
                    tradingStart = nil
                    tradingEnd   = nil
                }
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
