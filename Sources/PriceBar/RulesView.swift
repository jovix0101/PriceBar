import SwiftUI
import UserNotifications
import PriceBarCore

/// The popover that sets the alerts of one coin.
struct RulesView: View {
    let coin: String
    let store: Store

    @State private var metric: Metric = .price
    @State private var above = false
    @State private var threshold = ""
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(coin) 的提醒")
                .font(.headline)

            if authorization == .denied {
                permissionBanner
            }

            let rules = store.rules(for: coin)
            if rules.isEmpty {
                Text("还没有提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(rules) { rule in
                        RuleRow(rule: rule, store: store)
                    }
                }
            }

            Divider()
            form
        }
        .padding(14)
        .frame(width: 300)
        .task {
            authorization = await Notifier.authorization()
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("系统通知被关闭了，提醒不会弹出来。")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开通知设置") { Notifier.openSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 6))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("看什么", selection: $metric) {
                ForEach(Metric.allCases, id: \.self) { metric in
                    Text(metric.label).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Picker("方向", selection: $above) {
                    Text("高于").tag(true)
                    Text("低于").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)

                TextField("阈值", text: $threshold)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(add)

                Text(metric.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
            }

            Text(metric == .price
                 ? "阈值按美元填，与面板显示的货币无关。"
                 : "填正数即可：低于 5 表示跌 5%。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("添加提醒") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
    }

    private var canAdd: Bool {
        guard let value = Double(threshold.trimmingCharacters(in: .whitespaces)) else { return false }
        return metric == .change ? value > 0 : value > 0
    }

    private func add() {
        guard canAdd,
              let value = Double(threshold.trimmingCharacters(in: .whitespaces))
        else { return }

        let signed = metric == .change && !above ? -value : value
        store.addRule(Rule(coin: coin, metric: metric, above: above, threshold: signed))
        threshold = ""
        focused = true
    }
}

/// One rule: what it watches, whether it has fired, and how to change that.
private struct RuleRow: View {
    let rule: Rule
    let store: Store

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: rule.armed ? "bell" : "bell.slash")
                .font(.caption)
                .foregroundStyle(rule.armed ? Color.secondary : Color.orange)

            Text(description)
                .font(.caption)
                .monospacedDigit()

            Spacer(minLength: 0)

            if !rule.armed {
                Button("重新武装") { store.rearm(rule.id) }
                    .buttonStyle(.link)
                    .font(.caption2)
            }

            Button {
                store.removeRule(rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("删除这条提醒")
            .accessibilityLabel("删除 \(description)")
        }
        .padding(.vertical, 2)
    }

    private var description: String {
        let direction = rule.above ? "高于" : "低于"
        switch rule.metric {
        case .price:
            return "价格 \(direction) \(rule.thresholdText)"
        case .change:
            return "24h 涨跌幅 \(direction) \(rule.thresholdText)"
        }
    }
}

#Preview("提醒") {
    RulesView(coin: "BTC", store: Store(
        settings: {
            var settings = AppSettings()
            settings.rules = [
                Rule(coin: "BTC", metric: .price, above: true, threshold: 80000),
                Rule(coin: "BTC", metric: .change, above: false, threshold: -5),
            ]
            return settings
        }(),
        quotes: [Quote(coin: "BTC", price: 77424, change: 2.41)]
    ))
}
