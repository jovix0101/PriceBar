import SwiftUI
import PriceBarCore
import AppKit

/// The panel under the menu bar icon: the prices, then the way to change
/// them.
struct PanelView: View {
    let store: Store

    @State private var addingCoin = false
    /// Whether scroll bars sit beside the content or float over it. With a
    /// mouse plugged in, or "always show scroll bars" chosen, they take a
    /// strip of their own, and it changes while the app is running.
    @State private var scrollerStyle = NSScroller.preferredScrollerStyle

    /// The width of a row, whether the list scrolls or not. Wider by the
    /// room a "合约" tag needs once there is a contract on the panel, so that
    /// the tag does not come out of the price's side.
    private var rowWidth: CGFloat {
        280 + (store.hasContracts ? InstrumentName.wide - InstrumentName.narrow : 0)
    }

    /// What the panel lists, in the panel's order: a price for each
    /// instrument that has one, and a row saying why for each that does not.
    private var entries: [Entry] {
        let quoted = Dictionary(store.quotes.map { ($0.coin, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [Entry] = store.coins.compactMap { coin in
            if let quote = quoted[coin] { return .price(quote) }
            if let why = store.missing[coin] { return .missing(coin, why) }
            return nil
        }
        // A preview may hand the store prices for codes it never listed.
        let listed = Set(store.coins)
        out += store.quotes.filter { !listed.contains($0.coin) }.map(Entry.price)
        return out
    }

    private var scrolls: Bool {
        entries.count > store.panelRows
    }

    /// The strip a scroll bar takes beside the rows, or nothing when it floats
    /// over them. The panel grows by it rather than the rows giving it up:
    /// squeezed by those 15 points, a six-figure price breaks onto two lines.
    private var scrollerWidth: CGFloat {
        guard scrolls, scrollerStyle == .legacy else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    var body: some View {
        VStack(spacing: 0) {
            priceList
            Divider()
            footer
        }
        .frame(width: rowWidth + scrollerWidth)
        .padding(.vertical, 6)
        .onReceive(NotificationCenter.default.publisher(
            for: NSScroller.preferredScrollerStyleDidChangeNotification
        )) { _ in
            scrollerStyle = NSScroller.preferredScrollerStyle
        }
    }

    /// The prices, in a list that stops growing at the row limit and scrolls
    /// inside it instead. A panel that grew with every coin would sooner or
    /// later be taller than the screen, and its footer would be out of reach.
    private var priceList: some View {
        Group {
            if scrolls {
                ScrollView(.vertical) {
                    rows
                        .frame(width: rowWidth)
                }
                .frame(height: Self.height(for: store.panelRows))
            } else {
                rows
            }
        }
    }

    /// One row is 26 pt tall, spacing and all; the rest of the panel is the
    /// footer, the divider and the padding above and below them. Measured on
    /// the real panel at one, two, three, six and ten rows.
    static func height(for rows: Int) -> CGFloat {
        // Two points short of the rows' own height: the scroll view adds that
        // much of its own, and a panel that scrolls should be exactly as tall
        // as the same panel that does not.
        26 * CGFloat(rows) - 2
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                switch entry {
                case let .price(quote):
                    PriceRow(quote: quote, store: store)
                case let .missing(coin, why):
                    MissingRow(coin: coin, why: why, store: store)
                }
            }
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.error ?? "正在获取价格…")
                        .font(.caption)
                        .foregroundStyle(store.error == nil ? Color.secondary : Color.red)
                    if let hint = store.errorHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("立即刷新")
            .accessibilityLabel("刷新价格")

            Button {
                addingCoin = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("添加币种、贵金属或美股")
            .accessibilityLabel("添加币种、贵金属或美股")
            .popover(isPresented: $addingCoin, arrowEdge: .bottom) {
                AddCoinView(store: store)
            }

            Spacer()

            // The same list as the settings window, where it has room for
            // a preview: here it is the quick way to tick one more coin.
            Menu {
                ForEach(store.coins, id: \.self) { coin in
                    Button {
                        store.toggleMenuBar(coin)
                    } label: {
                        if store.isOnMenuBar(coin) {
                            Label(coin, systemImage: "checkmark")
                        } else {
                            Text(coin)
                        }
                    }
                }
                Divider()
                Button("菜单栏设置…") { SettingsWindow.shared.show(store: store, page: .menuBar) }
            } label: {
                Text(store.menuBarSummary)
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("菜单栏显示哪些币种")
            .accessibilityLabel("菜单栏显示哪些币种，现在\(store.menuBarSummary)")

            // A menu bar app must offer a way out: with no Dock icon and no
            // menu bar of its own, this menu and ⌘, are it.
            Menu {
                Button("设置…") { SettingsWindow.shared.show(store: store) }
                Divider()
                Button("退出 PriceBar") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("设置与退出")
            .accessibilityLabel("设置与退出")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// One coin: its name, its price, and how it moved in the last day.
private struct PriceRow: View {
    let quote: Quote
    let store: Store

    @State private var hovering = false
    @State private var showingRules = false

    /// The system's increase-contrast setting: the change is drawn heavier
    /// when the user asks for it.
    @Environment(\.colorSchemeContrast) private var contrast

    private var hasRules: Bool {
        !store.rules(for: quote.coin).isEmpty
    }

    private var code: String { Instrument(id: quote.coin).code }
    private var name: String { Instrument(id: quote.coin).name }

    var body: some View {
        HStack(spacing: 8) {
            InstrumentName(coin: quote.coin, wide: store.hasContracts)

            // A placeholder while the line is on its way, so that the prices
            // beside it do not shift when it arrives.
            if let line = store.lines[quote.coin] {
                // The line takes the ticker's side, not its own first-to-last
                // reading: the two are the same 24 hours counted a little
                // differently, and a red line beside a green number reads as
                // a bug even when both are right.
                Sparkline(values: line, color: changeColor)
            } else {
                Color.clear.frame(width: Sparkline.width, height: Sparkline.height)
            }

            Spacer(minLength: 4)

            // The symbol sits a size down and a shade back: it is a unit,
            // not a digit, and at the digits' size it reads as one more of
            // them.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(store.currency.symbol)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(store.amount(quote.price))
                    .font(.system(.body, weight: .medium))
                    .monospacedDigit()
            }
            // A price is one reading: broken over two lines it is two wrong
            // ones, so it keeps its width and the gap before it gives way.
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)

            // An arrow as well as a color: a red number alone tells a reader
            // who cannot tell red from green nothing.
            Text(changeText)
                .font(.system(.caption2, weight: contrast == .increased ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(changeColor)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 54, alignment: .trailing)

            // The space is always kept, so a row does not change width as
            // the pointer crosses it; the bell shows itself on hover, and
            // stays once the coin has alerts.
            Button {
                showingRules = true
            } label: {
                Image(systemName: hasRules ? "bell.fill" : "bell")
                    .font(.caption2)
                    .foregroundStyle(hasRules ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering || hasRules ? 1 : 0)
            .frame(width: 14)
            .help("\(name) 的提醒")
            .accessibilityLabel("\(name) 的提醒")
            .accessibilityHidden(!hovering && !hasRules)
            .popover(isPresented: $showingRules, arrowEdge: .bottom) {
                RulesView(coin: quote.coin, store: store)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            hovering ? Color.secondary.opacity(0.09) : .clear,
            in: .rect(cornerRadius: 6)
        )
        .contentShape(.rect)
        .onHover { hovering = $0 }
        // The whole row is the link: the numbers are what a reader points at,
        // and asking them to find a small icon for it would be a worse trade
        // than giving up a click on the row. The bell keeps its own click —
        // it is a button, and buttons answer before the row does. A reader
        // who clicks rows by accident can turn this off in the settings.
        .onTapGesture {
            if store.openContractOnClick { store.openContract(for: quote.coin) }
        }
        .help(store.openContractOnClick ? "在 \(store.source.label) 打开 \(code) 的合约行情" : "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(store.openContractOnClick ? "打开 \(store.source.label) 的合约行情页" : "")
        .contextMenu {
            Button("\(name) 的提醒…") { showingRules = true }
            Button("在 \(store.source.label) 打开合约行情") {
                store.openContract(for: quote.coin)
            }
            Button(store.isOnMenuBar(quote.coin) ? "从菜单栏移除" : "显示在菜单栏") {
                store.toggleMenuBar(quote.coin)
            }
            Divider()
            Button("移除 \(name)", role: .destructive) {
                store.removeCoin(quote.coin)
            }
        }
    }

    /// A thin space after the arrow, the same one the menu bar uses between
    /// its symbol and its number: the arrow points, it is not part of the
    /// figure, but a full space opens a gap wide enough to read as two
    /// separate readings.
    private var changeText: String {
        if quote.change > 0 { return "▲" + Self.thinSpace + formatSigned(quote.change) }
        if quote.change < 0 { return "▼" + Self.thinSpace + formatSigned(quote.change) }
        return formatSigned(quote.change)
    }

    private static let thinSpace = "\u{2009}"

    private var changeColor: Color {
        store.changeColors.color(for: quote.change)
    }

    private var accessibilityText: String {
        let direction = quote.change > 0 ? "上涨" : (quote.change < 0 ? "下跌" : "持平")
        return "\(name) \(store.money(quote.price))，24 小时\(direction) \(formatSigned(quote.change))"
    }
}

/// A row of the panel: a price, or a code with no price and the reason.
private enum Entry: Identifiable {
    case price(Quote)
    case missing(String, PriceAPI.Absence)

    var id: String {
        switch self {
        case let .price(quote): quote.coin
        case let .missing(coin, _): coin
        }
    }
}

/// The code at the head of a row, and for a contract a small "合约" after
/// it: BTC spot and BTC perpetual can sit on one panel, a few dollars apart,
/// and the tag is how they are told apart.
private struct InstrumentName: View {
    let coin: String
    /// Whether to keep the room a tag needs, on every row alike, so that
    /// the sparklines below each other still line up.
    let wide: Bool

    static let narrow: CGFloat = 42
    static let wide: CGFloat = 62

    var body: some View {
        let instrument = Instrument(id: coin)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(instrument.code)
                .font(.system(.caption, weight: .semibold))
            if instrument.market == .perpetual {
                Text(instrument.market.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(width: wide ? Self.wide : Self.narrow, alignment: .leading)
    }
}

/// An instrument the last read found no price for. It keeps its place, and
/// says why: a contract that vanished from the panel whenever its market was
/// out of reach would look like a contract that had been removed.
private struct MissingRow: View {
    let coin: String
    let why: PriceAPI.Absence
    let store: Store

    var body: some View {
        HStack(spacing: 8) {
            InstrumentName(coin: coin, wide: store.hasContracts)
            Spacer(minLength: 4)
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            // The price's own font, so the row is as tall as a row with one.
            Text("—")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(.tertiary)
            Color.clear.frame(width: 14, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .help(detail)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Instrument(id: coin).name)，\(detail)")
        .contextMenu {
            Button("移除 \(Instrument(id: coin).name)", role: .destructive) {
                store.removeCoin(coin)
            }
        }
    }

    private var reason: String {
        switch why {
        case .notListed: "\(store.source.label) 没有"
        case .unreachable: "连不上"
        }
    }

    private var detail: String {
        switch why {
        case .notListed:
            return "\(store.source.label) 没有 \(Instrument(id: coin).name)，换个数据源试试"
        case let .unreachable(message):
            let market = Instrument(id: coin).market
            return "\(message)。\(store.hint(for: store.source, market: market))"
        }
    }
}

/// A day of made-up prices, for the previews: a line is the shape of a day,
/// and a flat one would say nothing about it.
private func sampleLine(from start: Double, drift: Double, wobble: Double) -> [Double] {
    var value = start
    return (0..<24).map { hour in
        value *= 1 + drift + wobble * sin(Double(hour) * 1.1)
        return value
    }
}

private let sampleLines = [
    "BTC": sampleLine(from: 75_000, drift: 0.0012, wobble: 0.004),
    "ETH": sampleLine(from: 2_300, drift: 0.0021, wobble: 0.006),
    "SOL": sampleLine(from: 140, drift: 0.0014, wobble: 0.007),
]

#Preview("面板") {
    PanelView(store: Store(
        quotes: [
            Quote(coin: "BTC", price: 77424, change: 2.41),
            Quote(coin: "ETH", price: 2287, change: -0.87),
        ],
        lines: sampleLines
    ))
}

#Preview("人民币") {
    PanelView(store: Store(
        settings: {
            var settings = AppSettings()
            settings.currency = .cny
            return settings
        }(),
        quotes: [
            Quote(coin: "BTC", price: 77424, change: 2.41),
            Quote(coin: "ETH", price: 2287, change: -0.87),
        ],
        rate: 6.67,
        lines: sampleLines
    ))
}

#Preview("汇率还没到") {
    PanelView(store: Store(
        settings: {
            var settings = AppSettings()
            settings.currency = .cny
            return settings
        }(),
        quotes: [Quote(coin: "BTC", price: 77424, change: 2.41)],
        rate: nil
    ))
}

#Preview("拿不到行情") {
    PanelView(store: Store(quotes: [], error: "行情接口返回 HTTP 451"))
}
