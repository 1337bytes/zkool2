import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum MessageTool: String, CaseIterable, Identifiable {
    case encrypt = "Encrypt", decrypt = "Decrypt", sign = "Sign", verify = "Verify"
    var id: String { rawValue }
}

/// Settings demo for the same offline formats as the zec-offline-memo CLI.
struct MessageToolsView: View {
    @EnvironmentObject private var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    @State private var tool = MessageTool.encrypt
    @State private var pool: UInt8 = 1
    @State private var recipient = ""
    @State private var memo = ""
    @State private var payload = ""
    @State private var signedText = ""
    @State private var verifyingAddress = ""
    @State private var verifyingText = ""
    @State private var signature = ""
    @State private var working = false
    @State private var result: String?
    @State private var resultAddress: String?
    @State private var resultCaption = ""
    @State private var failure: String?
    @State private var copiedValue: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    Text("Offline messages").font(.largeTitle.bold())
                    Text("Encrypt or decrypt with Orchard and Ironwood. These operations do not create or broadcast transactions.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                    Picker("Operation", selection: $tool) {
                        ForEach(MessageTool.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.segmented).disabled(working)
                    form.disabled(working)
                    action
                    if let failure {
                        Text(failure).foregroundStyle(WalletTheme.coral).textSelection(.enabled)
                    }
                    resultView
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(WalletTheme.background).walletNavigationChrome()
        }.tint(WalletTheme.green).preferredColorScheme(.dark)
            .onChange(of: tool) { _ in clearResult() }
            .onChange(of: model.selectedAccountID) { _ in clearResult() }
            .onChange(of: [recipient, memo, payload, signedText, verifyingAddress, verifyingText, signature, String(pool)]) { _ in
                if !working { clearResult() }
            }
    }

    private var header: some View {
        HStack {
            Text(model.selectedAccount?.name ?? "Message tools").font(.headline)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").padding(10) }
                .buttonStyle(.plain).disabled(working).accessibilityLabel("Close message tools")
        }
    }

    @ViewBuilder private var form: some View {
        switch tool {
        case .encrypt:
            addressField("Recipient Unified Address", text: $recipient)
            Button {
                if let address = encryptionAddress { recipient = address }
            } label: {
                Label("Use selected account’s address", systemImage: "person.crop.circle")
            }.buttonStyle(WalletActionStyle()).disabled(encryptionAddress == nil)
            Picker("Envelope pool", selection: $pool) {
                Text("Orchard").tag(UInt8(0))
                Text("Ironwood").tag(UInt8(1))
            }.pickerStyle(.segmented)
            messageField("Message", text: $memo)
            Text("\(memo.utf8.count) / 512 UTF-8 bytes").font(WalletFont.numbers(12))
        case .decrypt:
            Text("Try the selected account’s viewing key. Imported viewing-key accounts can decrypt too.")
                .font(.footnote).foregroundStyle(Color.secondary)
            messageField("Encrypted message (base64)", text: $payload, clipboard: true)
        case .sign:
            experimentalNotice
            Text("Signs with this account’s software spending key and its Orchard-only address. The signing address is included with the result.")
                .font(.footnote).foregroundStyle(Color.secondary)
            messageField("Message to sign", text: $signedText)
        case .verify:
            experimentalNotice
            addressField("Signer’s Orchard-only address", text: $verifyingAddress)
            messageField("Original message", text: $verifyingText, clipboard: true, trimPasted: false)
            messageField("Signature (base64)", text: $signature, clipboard: true)
        }
    }

    private var experimentalNotice: some View {
        Label("Experimental ZOSF v1 · demo only", systemImage: "flask")
            .font(.footnote).foregroundStyle(WalletTheme.yellow)
    }

    private func addressField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Button { paste(into: text) } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.plain).foregroundStyle(WalletTheme.green)
                    .accessibilityLabel("Paste \(title)")
            }
            TextField(title, text: text).walletInput(url: true)
        }
    }

    private var encryptionAddress: String? {
        guard model.selectedAccount != nil, let orchard = model.overview?.address.orchard else { return nil }
        return model.overview?.address.ua ?? orchard
    }

    private func messageField(_ title: String, text: Binding<String>, clipboard: Bool = false, trimPasted: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            TextEditor(text: text).font(WalletFont.numbers(13)).frame(minHeight: 110)
                .scrollContentBackground(.hidden).walletInput()
                .accessibilityLabel(title)
            if clipboard {
                HStack(spacing: 12) {
                    copyButton(title, value: text.wrappedValue)
                    Button { paste(into: text, trimWhitespace: trimPasted) } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }.buttonStyle(WalletActionStyle())
                        .accessibilityLabel("Paste \(title)")
                }
            }
        }
    }

    private var action: some View {
        Button { Task { await run() } } label: {
            HStack {
                if working { ProgressView().tint(WalletTheme.background) }
                Text(working ? (tool == .sign ? "Generating proof…" : "Working…") : "\(tool.rawValue) message")
            }
        }.buttonStyle(WalletActionStyle(primary: true))
            .disabled(working || model.busy || model.wallet == nil || !validInput)
    }

    private var validInput: Bool {
        switch tool {
        case .encrypt: return !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && memo.utf8.count <= 512
        case .decrypt: return model.selectedAccountID != nil && !payload.isEmpty
        case .sign: return model.selectedAccountID != nil && signedText.utf8.count <= 1_048_576
        case .verify: return !verifyingAddress.isEmpty && !signature.isEmpty && verifyingText.utf8.count <= 1_048_576
        }
    }

    @ViewBuilder private var resultView: some View {
        if let result {
            VStack(alignment: .leading, spacing: 16) {
                Label(resultCaption, systemImage: "checkmark.circle.fill").foregroundStyle(WalletTheme.green)
                if let resultAddress { output("Address", value: resultAddress) }
                if tool != .verify { output(tool == .sign ? "Signature" : (tool == .encrypt ? "Encrypted message" : "Message"), value: result) }
                if tool == .encrypt {
                    Text("The payload is ready in Decrypt for a round-trip demo using the matching account.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                }
                if tool == .sign {
                    Text("The address, message, and signature are ready in Verify.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                }
            }.walletCard()
        }
    }

    private func output(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            Text(value.isEmpty ? "(empty message)" : value).font(WalletFont.numbers(12))
                .lineLimit(6).textSelection(.enabled)
            HStack(spacing: 12) {
                copyButton(title, value: value)
                ShareLink(item: value) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(WalletActionStyle())
                    .accessibilityLabel("Share \(title.lowercased())")
            }
        }
    }

    private func copyButton(_ title: String, value: String) -> some View {
        let copied = copiedValue == value
        return Button {
            #if os(iOS)
            UIPasteboard.general.string = value
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            #endif
            copiedValue = value
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
        }.buttonStyle(WalletActionStyle()).disabled(value.isEmpty)
            .accessibilityLabel("Copy \(title.lowercased())")
    }

    private func paste(into text: Binding<String>, trimWhitespace: Bool = true) {
        #if os(iOS)
        let value = UIPasteboard.general.string
        #else
        let value = NSPasteboard.general.string(forType: .string)
        #endif
        guard let value else {
            failure = "The clipboard does not contain text."
            return
        }
        clearResult()
        text.wrappedValue = trimWhitespace ? value.trimmingCharacters(in: .whitespacesAndNewlines) : value
    }

    private func clearResult() {
        result = nil
        resultAddress = nil
        failure = nil
        copiedValue = nil
    }

    @MainActor private func run() async {
        guard let wallet = model.wallet, !working, validInput else { return }
        let accountID = model.selectedAccountID
        let accountName = model.selectedAccount?.name ?? "Account"
        let operation = tool
        clearResult()
        working = true
        defer { working = false }
        do {
            switch operation {
            case .encrypt:
                let encrypted = try await wallet.encryptMessage(address: recipient, memo: memo, pool: pool)
                guard accountID == model.selectedAccountID else { return }
                result = encrypted
                payload = encrypted
                resultCaption = "Encrypted · \(pool == 0 ? "Orchard" : "Ironwood")"
            case .decrypt:
                guard let accountID else { return }
                let decrypted = try await wallet.decryptMessage(accountId: accountID, payload: payload)
                guard accountID == model.selectedAccountID else { return }
                result = decrypted.memo
                resultAddress = decrypted.address
                resultCaption = "Decrypted · \(decrypted.pool) · \(accountName)"
            case .sign:
                guard let accountID else { return }
                let signed = try await wallet.signMessage(accountId: accountID, message: signedText)
                guard accountID == model.selectedAccountID else { return }
                result = signed.signature
                resultAddress = signed.address
                verifyingAddress = signed.address
                verifyingText = signedText
                signature = signed.signature
                resultCaption = "Signed · \(accountName)"
            case .verify:
                try await wallet.verifyMessage(address: verifyingAddress, message: verifyingText, signature: signature)
                guard accountID == model.selectedAccountID else { return }
                result = "Verified"
                resultCaption = "Verified · Orchard spending authority"
            }
        } catch {
            guard accountID == model.selectedAccountID else { return }
            failure = operation == .verify ? "Not verified: \(error.localizedDescription)" : error.localizedDescription
        }
    }
}
