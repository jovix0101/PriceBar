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
        let strings = store.strings
        return VStack(alignment: .leading, spacing: 10) {
            Text(strings.alertsFor(Instrument(id: coin).name(strings)))
                .font(.headline)

            if authorization == .denied {
                permissionBanner
            }

            let rules = store.rules(for: coin)
            if rules.isEmpty {
                Text(strings.noAlerts)
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
        .takesKeyboard()
        .task {
            authorization = await Notifier.authorization()
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.strings.notificationsOff)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button(store.strings.openNotificationSettings) { Notifier.openSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 6))
    }

    private var form: some View {
        let strings = store.strings
        return VStack(alignment: .leading, spacing: 8) {
            Picker(strings.watchesLabel, selection: $metric) {
                ForEach(Metric.allCases, id: \.self) { metric in
                    Text(strings.label(metric)).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Picker(strings.directionLabel, selection: $above) {
                    Text(strings.aboveLabel).tag(true)
                    Text(strings.belowLabel).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)

                TextField(strings.thresholdLabel, text: $threshold)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(add)

                Text(metric.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
            }

            Text(metric == .price
                 ? strings.thresholdDollarsNote
                 : strings.thresholdPercentNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(strings.addAlert) { add() }
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
        let strings = store.strings
        return HStack(spacing: 6) {
            Image(systemName: rule.armed ? "bell" : "bell.slash")
                .font(.caption)
                .foregroundStyle(rule.armed ? Color.secondary : Color.orange)

            Text(description(strings))
                .font(.caption)
                .monospacedDigit()

            Spacer(minLength: 0)

            if !rule.armed {
                Button(strings.reEnable) { store.rearm(rule.id) }
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
            .help(strings.deleteThisAlert)
            .accessibilityLabel(strings.deleteNamed(description(strings)))
        }
        .padding(.vertical, 2)
    }

    private func description(_ strings: Strings) -> String {
        strings.ruleLine(
            strings.label(rule.metric),
            above: rule.above,
            threshold: rule.thresholdText
        )
    }
}

#Preview("Alerts") {
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
