import SwiftUI
import PriceBarCore

/// The settings window, opened with ⌘, or from the panel's menu.
///
/// Laid out by hand rather than with `Form`: the grouped form style gives
/// every row the height of the tallest control it might hold, which leaves
/// short rows padded out and the whole window loose. These rows are the
/// height of their contents, with the note under each group close enough to
/// belong to it.
struct SettingsView: View {
    let store: Store

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchProblem: String?
    /// The address is typed into a draft and applied when the field is left:
    /// a settings file rewritten on every keystroke, and a connection opened
    /// on every half-written address, is a lot of work for one line of text.
    @State private var proxyDraft = ""
    /// Whether the field has ever been shown, and so whether `proxyDraft`
    /// holds the saved address rather than its empty starting value.
    @State private var addressLoaded = false
    @State private var addressCommit: Task<Void, Never>?
    @FocusState private var addressFocused: Bool
    /// The coin being dragged, while it is being dragged.
    @State private var dragging: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("显示") {
                row("计价货币") {
                    Picker("", selection: Binding(
                        get: { store.currency },
                        set: { store.currency = $0 }
                    )) {
                        Text("美元 USD").tag(Currency.usd)
                        Text("人民币 CNY").tag(Currency.cny)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 202)
                }
                row("涨跌颜色") {
                    Picker("", selection: Binding(
                        get: { store.changeColors },
                        set: { store.changeColors = $0 }
                    )) {
                        Text("绿涨红跌").tag(ChangeColors.greenUp)
                        Text("红涨绿跌").tag(ChangeColors.redUp)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 202)
                }
            } note: {
                noteText(store.currency == .cny && store.rate == nil
                    ? "汇率还没取到，价格暂时显示为 —。"
                    : "汇率用欧洲央行的参考价，每天更新一次。")
            }

            group("行情") {
                row("刷新间隔") {
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
                    .frame(width: 202)
                }
            } note: {
                noteText("行情线取 24 小时，只在打开面板时更新。")
            }

            group("菜单栏") {
                row("显示币种", alignment: .top) {
                    coinList
                }
                row("文字颜色") {
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
                    .frame(width: 202)
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

            group("数据源与代理") {
                row("数据源") {
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
                    .frame(width: 202, alignment: .trailing)
                }
                row("代理") {
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
                    .frame(width: 202)
                }
                if store.proxyMode == .custom {
                    row("代理地址") {
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
                            .frame(width: 202)
                    }
                }
                row("连接测试") {
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
                } else {
                    noteText("代理只作用于当前选中的数据源。")
                }
            }

            group("启动") {
                row("登录时自动启动") {
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
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Pieces

    /// Every coin the panel lists, in the order it lists them, each with its
    /// place in the menu bar ticked. One list for both places: a coin dragged
    /// up here goes up there too.
    private var coinList: some View {
        VStack(spacing: 1) {
            ForEach(store.coins, id: \.self) { coin in
                coinRow(coin)
            }
        }
        .frame(width: 202)
    }

    private func coinRow(_ coin: String) -> some View {
        let on = store.isOnMenuBar(coin)
        return HStack(spacing: 6) {
            // A handle, not the whole row: the row has a checkbox on it, and
            // a drag that starts there would fight the click.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(coin)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 4)
            Button {
                store.toggleMenuBar(coin)
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(coin) 显示在菜单栏")
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
            Text(coin)
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

    /// A line of note, in the secondary colour unless something is wrong.
    private func noteText(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.leading, 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A titled group: its rows in a card, its note just below.
    private func group(
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
    private func row(
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

#Preview("设置") {
    SettingsView(store: Store(quotes: [
        Quote(coin: "BTC", price: 77424, change: 2.41),
        Quote(coin: "ETH", price: 2287, change: -0.87),
    ]))
}
