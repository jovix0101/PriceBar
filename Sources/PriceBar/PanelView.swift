import SwiftUI
import PriceBarCore
import AppKit

/// The panel under the menu bar icon: the prices, then the way to change
/// them.
struct PanelView: View {
    let store: Store

    @State private var addingCoin = false

    var body: some View {
        VStack(spacing: 0) {
            priceList
            Divider()
            footer
        }
        .frame(width: 280)
        .padding(.vertical, 6)
    }

    /// The prices, in a list that stops growing at the row limit and scrolls
    /// inside it instead. A panel that grew with every coin would sooner or
    /// later be taller than the screen, and its footer would be out of reach.
    private var priceList: some View {
        Group {
            if store.quotes.count > store.panelRows {
                ScrollView(.vertical) {
                    rows
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
            ForEach(store.quotes) { quote in
                PriceRow(quote: quote, store: store)
            }
            if store.quotes.isEmpty {
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
            .help("添加币种")
            .accessibilityLabel("添加币种")
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
                Button("菜单栏设置…") { SettingsWindow.shared.show(store: store) }
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

    var body: some View {
        HStack(spacing: 8) {
            Text(quote.coin)
                .font(.system(.caption, weight: .semibold))
                .frame(width: 42, alignment: .leading)

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

            // An arrow as well as a color: a red number alone tells a reader
            // who cannot tell red from green nothing.
            Text(changeText)
                .font(.system(.caption2, weight: contrast == .increased ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(changeColor)
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
            .help("\(quote.coin) 的提醒")
            .accessibilityLabel("\(quote.coin) 的提醒")
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
        // it is a button, and buttons answer before the row does.
        .onTapGesture { store.openContract(for: quote.coin) }
        .help("在 \(store.source.label) 打开 \(quote.coin) 的合约行情")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("打开 \(store.source.label) 的合约行情页")
        .contextMenu {
            Button("\(quote.coin) 的提醒…") { showingRules = true }
            Button("在 \(store.source.label) 打开合约行情") {
                store.openContract(for: quote.coin)
            }
            Button(store.isOnMenuBar(quote.coin) ? "从菜单栏移除" : "显示在菜单栏") {
                store.toggleMenuBar(quote.coin)
            }
            Divider()
            Button("移除 \(quote.coin)", role: .destructive) {
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
        return "\(quote.coin) \(store.money(quote.price))，24 小时\(direction) \(formatSigned(quote.change))"
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
