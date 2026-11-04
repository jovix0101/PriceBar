import SwiftUI
import PriceBarCore

/// The popover that adds a coin: a code, checked against the exchange before
/// it is added.
struct AddCoinView: View {
    let store: Store

    @State private var text = ""
    @State private var problem: String?
    @State private var checking = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加币种")
                .font(.headline)

            TextField("代号，例如 SOL", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(checking)
                .onSubmit(submit)
                .onChange(of: text) { problem = nil }

            Text(problem ?? "填交易所的代号，如 BTC、ETH、DOGE。")
                .font(.caption)
                .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(width: 250)
        .onAppear { focused = true }
    }

    private var canSubmit: Bool {
        !checking && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        checking = true
        problem = nil

        Task {
            let failure = await store.addCoin(text)
            checking = false
            if let failure {
                problem = failure
            } else {
                dismiss()
            }
        }
    }
}

#Preview("添加币种") {
    AddCoinView(store: Store())
}
