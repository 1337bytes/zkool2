import SwiftUI

struct RenameAccountView: View {
    @EnvironmentObject private var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let account: AccountSummary
    @State private var name: String

    init(account: AccountSummary) {
        self.account = account
        _name = State(initialValue: account.name)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Rename account").font(.largeTitle.bold())
                TextField("Account name", text: $name).walletInput().disabled(model.busy)
                if let message = model.message { Text(message).foregroundStyle(WalletTheme.coral) }
                Button("Save name") {
                    Task { if await model.renameAccount(account.id, name: name) { dismiss() } }
                }.buttonStyle(WalletActionStyle(primary: true))
                    .disabled(model.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { dismiss() }.buttonStyle(WalletActionStyle()).disabled(model.busy)
                Spacer()
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
                .background(WalletTheme.background).walletNavigationChrome()
        }.tint(WalletTheme.green).preferredColorScheme(.dark)
    }
}

struct TransactionDetailsView: View {
    @EnvironmentObject private var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let accountID: Int32
    let accountName: String
    let transaction: WalletTransaction
    @State private var details: TransactionDetailsResponse?
    @State private var failure: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(transaction.title).font(.title.bold())
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").padding(10) }.buttonStyle(.plain)
                    }
                    Text(accountName).font(.headline).foregroundStyle(WalletTheme.green)
                    Text("\(WalletMoney.format(transaction.value)) ZEC").font(WalletFont.numbers(26, bold: true))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transaction ID").font(.headline)
                        Text(transaction.txid).font(WalletFont.numbers(12)).textSelection(.enabled)
                        ShareLink(item: transaction.txid) { Label("Share transaction ID", systemImage: "square.and.arrow.up") }
                            .buttonStyle(WalletActionStyle())
                        Text(transaction.height > 0 ? "Block \(transaction.height)" : "Unconfirmed")
                            .font(WalletFont.numbers(13))
                        Text(transaction.time).font(.footnote).foregroundStyle(Color.secondary)
                    }.walletCard()
                    loadedDetails
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(WalletTheme.background).walletNavigationChrome()
        }.tint(WalletTheme.green).preferredColorScheme(.dark)
            .task { await load() }
    }

    @ViewBuilder private var loadedDetails: some View {
        if loading { ProgressView("Loading transaction…") }
        if let failure {
            Text(failure).foregroundStyle(WalletTheme.coral)
            Button("Retry") { Task { await load() } }.buttonStyle(WalletActionStyle()).disabled(loading)
        }
        if let details {
            Text("Fee · \(WalletMoney.format(details.transaction.fee)) ZEC").font(WalletFont.numbers(13))
            VStack(alignment: .leading, spacing: 16) {
                Text("Memos").font(.headline)
                if details.memos.isEmpty { Text("No text memo.").foregroundStyle(Color.secondary) }
                ForEach(Array(details.memos.enumerated()), id: \.offset) { _, memo in
                    Text(memo).textSelection(.enabled)
                }
            }.walletCard()
            if !details.transaction.outputs.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Outputs").font(.headline)
                    ForEach(details.transaction.outputs) { output in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(output.poolName) · \(WalletMoney.format(output.value)) ZEC")
                                .font(WalletFont.numbers(13))
                            Text(output.address).font(WalletFont.numbers(11)).textSelection(.enabled)
                        }
                    }
                }.walletCard()
            }
        }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            let response = try await model.transactionDetails(accountID: accountID, transaction: transaction)
            if !Task.isCancelled { details = response }
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
    }
}
