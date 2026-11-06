import SwiftUI
import PriceBarCore

/// A page of the settings window. One long window had grown past the height
/// of a laptop screen; split by what each page is about, none of them does.
enum SettingsPage: Int, CaseIterable {
    case general, menuBar, panel, source

    var title: String {
        switch self {
        case .general: "通用"
        case .menuBar: "菜单栏"
        case .panel: "面板"
        case .source: "数据源"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .panel: "list.bullet.rectangle"
        case .source: "network"
        }
    }
}

/// One page of the settings window, opened with ⌘, or from the panel's menu.
///
/// Laid out by hand rather than with `Form`: the grouped form style gives
/// every row the height of the tallest control it might hold, which leaves
/// short rows padded out and the whole window loose. These rows are the
/// height of their contents, with the note under each group close enough to
/// belong to it.
struct SettingsView: View {
    let store: Store
    let page: SettingsPage

    var body: some View {
        Group {
            switch page {
            case .general: GeneralSettings(store: store)
            case .menuBar: MenuBarSettings(store: store)
            case .panel: PanelSettings(store: store)
            case .source: SourceSettings(store: store)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pages

/// Currency, colours, how often to refresh, and starting at login.
private struct GeneralSettings: View {
    let store: Store

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup("显示") {
                settingsRow("计价货币") {
                    Picker("", selection: Binding(
                        get: { store.currency },
                        set: { store.currency = $0 }
                    )) {
                        Text("美元 USD").tag(Currency.usd)
                        Text("人民币 CNY").tag(Currency.cny)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: controlWidth)
                }
                settingsRow("涨跌颜色") {
                    Picker("", selection: Binding(
                        get: { store.changeColors },
                        set: { store.changeColors = $0 }
                    )) {
                        Text("绿涨红跌").tag(ChangeColors.greenUp)
                        Text("红涨绿跌").tag(ChangeColors.redUp)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: controlWidth)
                }
            } note: {
                noteText(store.currency == .cny && store.rate == nil
                    ? "汇率还没取到，价格暂时显示为 —。"
                    : "汇率用欧洲央行的参考价，每天更新一次。")
            }

            settingsGroup("行情") {
                settingsRow("刷新间隔") {
                    Picker("", selection: Binding(
                        get: { store.interval },
                        set: { store.interval = $0 }
                    )) {
                        Text("5 秒").tag(5.0)
                        Text("10 秒").tag(10.0)
                        Text("30 秒").tag(30.0)
                        Text("1 分钟").tag(60.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: controlWidth)
                }
            } note: {
                noteText("行情线取 24 小时，只在打开面板时更新。")
            }

            settingsGroup("启动") {
                settingsRow("登录时自动启动") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { turnOn in
                            launchAtLogin = turnOn
                            launchProblem = LoginItem.setEnabled(turnOn)
                            // The system is the authority: read back what it did.
                            launchAtLogin = LoginItem.isEnabled
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!LoginItem.supported)
                }
            } note: {
                noteText(
                    launchProblem ?? (LoginItem.supported
                        ? "登录后 PriceBar 会直接出现在菜单栏。"
                        : "要以 .app 运行才能设开机自启。"),
                    color: launchProblem == nil ? .secondary : .red
                )
            }
        }
    }
}

/// Which coins the menu bar shows, in what order, in what colour.
private struct MenuBarSettings: View {
    let store: Store

    /// The coin being dragged, while it is being dragged.
    @State private var dragging: String?

    var body: some View {
        settingsGroup("菜单栏") {
            settingsRow("显示币种", alignment: .top) {
                coinList
            }
            settingsRow("文字颜色") {
                Picker("", selection: Binding(
                    get: { store.menuBarTint },
                    set: { store.menuBarTint = $0 }
                )) {
                    ForEach(MenuBarTint.allCases, id: \.self) { tint in
                        Text(tint.label).tag(tint)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: controlWidth)
            }
            // Full width, not the control column: three coins do not fit
            // in 202 points, and a preview shrunk to fit says nothing
            // about how the colours read.
            preview
                .padding(.vertical, 7)
        } note: {
            if store.menuBarCoins.isEmpty {
                noteText("没勾选时显示面板里的第一个币种。", color: .orange)
            } else if store.menuBarCoins.count > 1 {
                noteText("勾选的币种并排显示，从左到右就是这个顺序。")
            } else {
                noteText("勾选的币种显示在菜单栏。")
            }
            noteText("拖动左边的把手可以调顺序，这个顺序也是面板里的顺序。")
            if store.coins.count > visibleCoinRows {
                noteText("币种多了列表可以滚动，共 \(store.coins.count) 个。")
            }
            switch store.menuBarTint {
            case .automatic:
                noteText("自动：跟着菜单栏自己的颜色走，换壁纸、切深浅色都能看清。")
            case .change:
                noteText("随涨跌：每个币种按自己的涨跌着色，和面板里的百分比同一个颜色。")
                noteText("涨跌幅正好为 0 时没有方向，交回系统着色。")
            case .dark, .light:
                noteText("固定用\(store.menuBarTint.label)，不随下次换壁纸变化。")
            }
        }
    }

    /// Every coin the panel lists, in the order it lists them, each with its
    /// place in the menu bar ticked. One list for both places: a coin dragged
    /// up here goes up there too.
    private var coinList: some View {
        Group {
            if store.coins.count > visibleCoinRows {
                // Nothing else on the page grows with the number of coins,
                // so the list is the one thing allowed to scroll: a dozen
                // coins would otherwise push the window past the bottom of
                // the screen.
                ScrollView {
                    coinRows
                }
                .frame(height: coinRowHeight * CGFloat(visibleCoinRows))
            } else {
                coinRows
            }
        }
        .frame(width: controlWidth)
    }

    private var coinRows: some View {
        VStack(spacing: 1) {
            ForEach(store.coins, id: \.self) { coin in
                coinRow(coin)
            }
        }
    }

    /// How many coins the page shows before the list starts scrolling, and
    /// how tall one row is.
    private let visibleCoinRows = 6
    /// A row: 12 pt of text, 3 pt above and below, and the hairline between.
    private let coinRowHeight: CGFloat = 21

    private func coinRow(_ coin: String) -> some View {
        let on = store.isOnMenuBar(coin)
        return HStack(spacing: 6) {
            // A handle, not the whole row: the row has a checkbox on it, and
            // a drag that starts there would fight the click.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(Instrument(id: coin).code)
                .font(.system(size: 12, weight: .medium))
            if Instrument(id: coin).market == .perpetual {
                Text(Market.perpetual.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                store.toggleMenuBar(coin)
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Instrument(id: coin).name) 显示在菜单栏")
            .accessibilityValue(on ? "已选" : "未选")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            dragging == coin ? Color.secondary.opacity(0.14) : .clear,
            in: .rect(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .onDrag {
            dragging = coin
            return NSItemProvider(object: coin as NSString)
        } preview: {
            Text(Instrument(id: coin).name)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: .rect(cornerRadius: 5))
        }
        .onDrop(
            of: [.text],
            delegate: CoinDrop(coin: coin, dragging: $dragging) { moved, onto in
                store.moveCoin(moved, onto: onto)
            }
        )
    }

    /// The menu bar label, set the way the menu bar sets it: reading a preview
    /// of one coin cannot tell you whether three fit.
    private var preview: some View {
        Text(AttributedString(MenuBarPrice.title(for: store)))
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backdrop, in: .rect(cornerRadius: 6))
    }

    /// The swatch behind the preview. A label drawn in a colour of its own
    /// needs the menu bar it was chosen for behind it, or the light one would
    /// be white on white and say nothing.
    private var backdrop: AnyShapeStyle {
        switch store.menuBarTint {
        // Green and red are read against the wallpaper like any other
        // menu bar item, so the swatch for "随涨跌" is the same neutral
        // one "自动" sits on.
        case .automatic, .change: AnyShapeStyle(.quaternary.opacity(0.5))
        case .dark: AnyShapeStyle(Color.white.opacity(0.9))
        case .light: AnyShapeStyle(Color.black.opacity(0.75))
        }
    }
}

/// How tall the panel grows, and what a click on a coin does.
private struct PanelSettings: View {
    let store: Store

    /// Whether the row limit is one of the user's own rather than a preset.
    /// Kept apart from the limit itself: picking "自定义" while the limit is
    /// still 8 has to show the field, not snap back to the preset.
    @State private var custom: Bool

    init(store: Store) {
        self.store = store
        _custom = State(initialValue: !Self.rowChoices.contains(store.panelRows))
    }

    /// The row limits offered as presets, in the order they are offered.
    private static let rowChoices = [6, 8, 10, 12]
    /// The preset that stands for "a number of my own".
    private static let customTag = 0

    var body: some View {
        settingsGroup("面板") {
            settingsRow("最多显示") {
                Picker("", selection: Binding(
                    get: { custom ? Self.customTag : store.panelRows },
                    set: { choice in
                        custom = choice == Self.customTag
                        if !custom { store.panelRows = choice }
                    }
                )) {
                    ForEach(Self.rowChoices, id: \.self) { rows in
                        Text("\(rows) 行").tag(rows)
                    }
                    Text("自定义").tag(Self.customTag)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 236)
            }
            if custom {
                settingsRow("自定义行数") {
                    HStack(spacing: 6) {
                        TextField("", value: rows, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 48)
                        Text("行")
                            .font(.system(size: 13))
                        Stepper("", value: rows, in: AppSettings.panelRowRange)
                            .labelsHidden()
                    }
                }
            }
            settingsRow("点击币种打开合约行情") {
                Toggle("", isOn: Binding(
                    get: { store.openContractOnClick },
                    set: { store.openContractOnClick = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        } note: {
            noteText("币种多过这几行，面板里滚动，不挡住下面的窗口。")
            if custom {
                noteText("自定义可设 \(AppSettings.panelRowRange.lowerBound)–\(AppSettings.panelRowRange.upperBound) 行。")
            }
            noteText(store.openContractOnClick
                ? "点一下面板里的币种，在浏览器打开 \(store.source.label) 的合约行情。"
                : "点击面板里的币种不再跳转；右键菜单里仍能打开合约行情。")
        }
    }

    /// The row limit, kept inside the range whatever is typed: a field that
    /// accepted 0 would empty the panel, one that accepted 500 would put its
    /// footer below the screen.
    private var rows: Binding<Int> {
        Binding(
            get: { store.panelRows },
            set: { typed in
                let range = AppSettings.panelRowRange
                store.panelRows = min(max(typed, range.lowerBound), range.upperBound)
            }
        )
    }
}

/// Where the prices come from, and how the app gets there.
private struct SourceSettings: View {
    let store: Store

    /// The address is typed into a draft and applied when the field is left:
    /// a settings file rewritten on every keystroke, and a connection opened
    /// on every half-written address, is a lot of work for one line of text.
    @State private var proxyDraft = ""
    /// Whether the field has ever been shown, and so whether `proxyDraft`
    /// holds the saved address rather than its empty starting value.
    @State private var addressLoaded = false
    @State private var addressCommit: Task<Void, Never>?
    @FocusState private var addressFocused: Bool

    var body: some View {
        settingsGroup("数据源与代理") {
            settingsRow("数据源") {
                Picker("", selection: Binding(
                    get: { store.source },
                    set: { store.source = $0 }
                )) {
                    ForEach(MarketSource.allCases, id: \.self) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: controlWidth, alignment: .trailing)
            }
            settingsRow("代理") {
                Picker("", selection: Binding(
                    get: { store.proxyMode },
                    // Leaving the custom row takes the address with it: the
                    // field goes away without ever losing focus, so the
                    // draft is written down before the mode changes.
                    set: { commitAddress(); store.proxyMode = $0 }
                )) {
                    Text("直连").tag(ProxyMode.direct)
                    Text("跟随系统").tag(ProxyMode.system)
                    Text("自定义").tag(ProxyMode.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: controlWidth)
            }
            if store.proxyMode == .custom {
                settingsRow("代理地址") {
                    TextField("http://127.0.0.1:1080", text: $proxyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .focused($addressFocused)
                        .onSubmit { commitAddress() }
                        .onChange(of: addressFocused) { _, focused in
                            if !focused { commitAddress() }
                        }
                        .onAppear {
                            proxyDraft = store.proxyAddress
                            addressLoaded = true
                        }
                        // Written as it is typed, a half-written address
                        // would open a connection per keystroke, so it
                        // waits for a pause in the typing.
                        .onChange(of: proxyDraft) { _, _ in scheduleCommit() }
                        .frame(width: controlWidth)
                }
            }
            settingsRow("连接测试") {
                HStack(spacing: 6) {
                    if store.testing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("测试") {
                        commitAddress()
                        store.testConnection()
                    }
                    .disabled(store.testing)
                }
            }
        } note: {
            if let problem = store.proxyProblem {
                noteText(problem, color: .red)
            } else if store.testing {
                noteText("正在连接 \(store.source.label)…")
            } else if let result = store.connectionTest {
                noteText(result.text, color: result.ok ? .secondary : .red)
            } else if store.source.normallyNeedsProxy {
                noteText("\(store.source.label) 通常要挂代理才能连上，先测一次再决定。")
            } else if store.hasContracts, store.source.normallyNeedsProxy(for: .perpetual) {
                noteText("\(store.source.label) 的现货能直连，合约通常要挂代理，先测一次再决定。")
            } else {
                noteText("代理只作用于当前选中的数据源。")
            }
        }
        // The page can be left with the address half typed: switching tabs
        // takes the field away without it ever losing focus.
        .onDisappear { commitAddress() }
    }

    /// Writes the typed address down half a second after the typing stops,
    /// and cancels the wait if it is already going to be written.
    private func scheduleCommit() {
        addressCommit?.cancel()
        addressCommit = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            commitAddress()
        }
    }

    private func commitAddress() {
        addressCommit?.cancel()
        addressCommit = nil
        // Nothing has been typed or shown yet: an empty draft would write an
        // empty address over the one that is saved.
        guard addressLoaded else { return }
        let address = proxyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address != store.proxyAddress else { return }
        store.proxyAddress = address
    }
}

// MARK: - Pieces

/// The width of the control column, so that the controls of one page line up
/// down its right edge.
private let controlWidth: CGFloat = 202

/// A line of note, in the secondary colour unless something is wrong.
@MainActor
private func noteText(_ text: String, color: Color = .secondary) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(color)
        .padding(.leading, 2)
        .fixedSize(horizontal: false, vertical: true)
}

/// A titled group: its rows in a card, its note just below.
@MainActor
private func settingsGroup(
    _ title: String,
    @ViewBuilder rows: () -> some View,
    @ViewBuilder note: () -> some View
) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)

        VStack(spacing: 0) {
            rows()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))

        note()
    }
}

/// A labelled row: the name on the left, the control against the right
/// edge, both on the same line.
@MainActor
private func settingsRow(
    _ label: String,
    alignment: VerticalAlignment = .center,
    @ViewBuilder control: () -> some View
) -> some View {
    HStack(alignment: alignment, spacing: 10) {
        Text(label)
            .font(.system(size: 13))
        Spacer(minLength: 8)
        control()
    }
    .padding(.vertical, 7)
    .frame(minHeight: 32)
}

/// Puts the dragged coin in front of the row the pointer is over, as it goes:
/// the list rearranges under the hand rather than after the drop.
private struct CoinDrop: DropDelegate {
    let coin: String
    @Binding var dragging: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != coin else { return }
        move(dragging, coin)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

#Preview("面板设置") {
    SettingsView(store: Store(quotes: [
        Quote(coin: "BTC", price: 77424, change: 2.41),
        Quote(coin: "ETH", price: 2287, change: -0.87),
    ]), page: .panel)
}
