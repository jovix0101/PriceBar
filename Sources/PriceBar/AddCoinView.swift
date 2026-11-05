import SwiftUI
import PriceBarCore

/// The popover that adds a coin, a metal or a stock: a code, checked against
/// the exchange's markets before it is added.
///
/// A code only one market lists — a stock, a metal, a coin with no contract
/// — is added as soon as the exchange answers. A code both list is the
/// user's choice: spot is ticked, and the contract can be ticked beside it.
struct AddCoinView: View {
    let store: Store

    @State private var text = ""
    @State private var problem: String?
    @State private var checking = false
    /// The markets on offer for the code as it was looked up, once both
    /// answered; nil while there is nothing to choose.
    @State private var choices: [CoinValidation.Choice]?
    @State private var picked: Set<Instrument> = []
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: Store) {
        self.store = store
    }

    /// Opened on a choice already looked up, for the previews.
    init(store: Store, code: String, choices: [CoinValidation.Choice]) {
        self.store = store
        _text = State(initialValue: code)
        _choices = State(initialValue: choices)
        _picked = State(initialValue: Set(choices.filter { $0.state == .available && $0.instrument.market == .spot }.map(\.instrument)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加")
                .font(.headline)

            TextField("代号，例如 SOL、XAU、AAPL", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(checking)
                .onSubmit(submit)
                .onChange(of: text) {
                    problem = nil
                    choices = nil
                    picked = []
                }

            if let choices {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(choices, id: \.instrument) { choice in
                        choiceRow(choice)
                    }
                }
                Text("合约价跟着现货走，平时会差一点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(problem ?? "币填 BTC、ETH；黄金 XAU、白银 XAG；美股填代码，如 AAPL、TSLA。")
                    .font(.caption)
                    .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if checking {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { focused = true }
    }

    /// One market: a box to tick when it can be added, or the reason it
    /// cannot, greyed out.
    private func choiceRow(_ choice: CoinValidation.Choice) -> some View {
        let instrument = choice.instrument
        let enabled = choice.state == .available
        return Toggle(isOn: Binding(
            get: { picked.contains(instrument) },
            set: { on in
                if on { picked.insert(instrument) } else { picked.remove(instrument) }
            }
        )) {
            HStack(spacing: 6) {
                Text(instrument.market == .spot ? "现货" : "永续合约")
                // What sets the two apart. On Binance both are named ETHUSDT,
                // so the name would say nothing.
                Text(instrument.market == .spot ? "\(instrument.code)/USDT" : "USDT 结算 · 不到期")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                switch choice.state {
                case .available:
                    EmptyView()
                case .added:
                    Text("已添加")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unreachable:
                    Text("连不上")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!enabled)
        .help(help(for: choice))
    }

    private func help(for choice: CoinValidation.Choice) -> String {
        switch choice.state {
        case .available: ""
        case .added: "\(choice.instrument.name) 已经在面板里"
        case let .unreachable(message):
            "\(message)。\(store.hint(for: store.source, market: choice.instrument.market))"
        }
    }

    private var canSubmit: Bool {
        guard !checking else { return false }
        if choices != nil { return !picked.isEmpty }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        // The choice is made: add what is ticked.
        if choices != nil {
            store.add(Array(picked).sorted { $0.market == .spot && $1.market != .spot })
            dismiss()
            return
        }

        checking = true
        problem = nil
        Task {
            let decision = await store.lookUp(text)
            checking = false
            switch decision {
            case let .problem(message):
                problem = message
            case let .add(instrument):
                store.add([instrument])
                dismiss()
            case let .choose(offered):
                choices = offered
                // Spot is what a code has always meant here; the contract is
                // the extra a user asks for.
                let available = offered.filter { $0.state == .available }.map(\.instrument)
                picked = Set(available.first { $0.market == .spot }.map { [$0] } ?? Array(available.prefix(1)))
            }
        }
    }
}

#Preview("添加") {
    AddCoinView(store: Store())
}

#Preview("现货和合约都有") {
    AddCoinView(store: Store(), code: "BTC", choices: [
        .init(instrument: Instrument(code: "BTC", market: .spot), state: .available),
        .init(instrument: Instrument(code: "BTC", market: .perpetual), state: .available),
    ])
}
