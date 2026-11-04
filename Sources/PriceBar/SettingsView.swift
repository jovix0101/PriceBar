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
                row("轮播币种") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 62), spacing: 6)],
                        spacing: 6
                    ) {
                        ForEach(store.coins, id: \.self) { coin in
                            chip(coin)
                        }
                    }
                    .frame(width: 202)
                }
                row("切换间隔") {
                    Picker("", selection: Binding(
                        get: { store.rotateInterval },
                        set: { store.rotateInterval = $0 }
                    )) {
                        Text("3 秒").tag(3.0)
                        Text("5 秒").tag(5.0)
                        Text("10 秒").tag(10.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 202)
                    .disabled(store.menuBarCoins.count < 2)
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
                row("预览") {
                    preview
                }
            } note: {
                if store.menuBarCoins.isEmpty {
                    noteText("没勾选时显示面板里的第一个币种。", color: .orange)
                } else if store.menuBarCoins.count < 2 {
                    noteText("勾选两个以上币种，菜单栏才开始轮播。")
                } else {
                    noteText("按面板里的顺序轮播，打开面板时暂停。")
                }
                switch store.menuBarTint {
                case .automatic:
                    noteText("自动：菜单栏按壁纸明暗自己着色，图标跟着系统变。")
                case .change:
                    noteText("随涨跌：跟着上面「涨跌颜色」走，和面板里的百分比同一个色。")
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

    /// One coin on the menu bar's list: ticked, it takes a turn there.
    private func chip(_ coin: String) -> some View {
        let on = store.isOnMenuBar(coin)
        return Button {
            store.toggleMenuBar(coin)
        } label: {
            HStack(spacing: 3) {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(coin)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                in: .capsule
            )
            .foregroundStyle(on ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("菜单栏轮播 \(coin)")
        .accessibilityValue(on ? "已选" : "未选")
    }

    /// The menu bar label itself, drawn by the same code the menu bar uses,
    /// turning at the interval chosen above: reading the numbers cannot tell
    /// you whether three seconds is too fast.
    private var preview: some View {
        HStack(spacing: 4) {
            if let image = MenuBarPrice.image(for: store) {
                Image(nsImage: image)
                    .renderingMode(MenuBarPrice.tint(for: store) == nil ? .template : .original)
                    .foregroundStyle(.primary)
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 7)
        .frame(minHeight: 32)
    }
}

#Preview("设置") {
    SettingsView(store: Store(quotes: [
        Quote(coin: "BTC", price: 77424, change: 2.41),
        Quote(coin: "ETH", price: 2287, change: -0.87),
    ]))
}
