import Foundation
import SwiftUI
import AppKit
import CoreText
import Vision

// Host integration and offscreen visual check; uses real temporary wallets, no sample balances.
@main
struct WalletUISmoke {
    @MainActor
    static func main() async throws {
        WalletFont.register(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("native/ios/Resources/Fonts"))
        let numberFont = CTFontCreateWithName("IBMPlexMono-Regular" as CFString, 18, nil)
        precondition((CTFontCopyPostScriptName(numberFont) as String) == "IBMPlexMono-Regular")
        precondition(PaymentDraft.validAmount("0.00000001"))
        for value in ["", "0", "-1", "1e8", "0.000000001", "21000000.00000001"] {
            precondition(!PaymentDraft.validAmount(value))
        }
        precondition(PaymentDraft.appending("9", to: "1.12345678") == "1.12345678")
        precondition(PaymentDraft.appending(".", to: "1.2") == "1.2")
        precondition(PaymentDraft.memo(subject: "Hello", text: "Memo", returnAddress: "u-test") == "Subject: Hello\nMemo\nReply to: u-test")
        precondition(WalletServerMode.localEndpoint(serverType: 0) == "http://127.0.0.1:8137")
        precondition(WalletServerMode.localEndpoint(serverType: 1) == "http://127.0.0.1:18232")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wallet = try await Wallet.open(config: WalletConfig(
            dataDirectory: directory.path, databaseName: "ui-test.db", network: 2,
            serverUrl: "http://127.0.0.1:1", serverType: 0,
            databasePassword: "ui-smoke-only", allowUnencryptedDatabase: false
        ))
        let model = WalletModel(wallet: wallet)
        let created = await model.addAccount(name: "Main Wallet", key: nil, birth: 1)
        precondition(created && model.accounts.count == 1)
        precondition(model.recovery?.phrase.split(separator: " ").count == 24)
        precondition(model.overview?.address.ua != nil)
        try verifyReceivingCodes(model)
        let firstID = model.selectedAccountID!
        let previousAddress = model.overview!.address.ua!
        let freshAddress = await model.newReceiveAddress()
        precondition(freshAddress)
        precondition(model.overview?.address.ua != previousAddress)
        let oldAddressPayload = try await wallet.encryptMessage(address: previousAddress, memo: "Old address still works", pool: 1)
        let oldAddressMemo = try await wallet.decryptMessage(accountId: firstID, payload: oldAddressPayload)
        precondition(oldAddressMemo.memo == "Old address still works")
        let missing = WalletTransaction(id: 1, txid: String(repeating: "0", count: 64), height: 0, time: "", value: "0")
        do {
            _ = try await model.transactionDetails(accountID: firstID, transaction: missing)
            preconditionFailure("Missing transaction accepted")
        } catch {
            precondition(error.localizedDescription.contains("Unknown txid"), error.localizedDescription)
        }
        for pool: UInt8 in [0, 1] {
            let payload = try await wallet.encryptMessage(address: model.overview!.address.ua!, memo: "Swift demo 🔐", pool: pool)
            let decrypted = try await wallet.decryptMessage(accountId: firstID, payload: payload)
            precondition(decrypted.memo == "Swift demo 🔐")
            precondition(decrypted.pool == (pool == 0 ? "Orchard" : "Ironwood"))
        }
        let spendable = try await wallet.spendablePools(accountId: firstID, height: 1, confirmations: 0)
        precondition(spendable == ["0", "0", "0", "0"])
        do {
            _ = try await wallet.preparePayment(request: PaymentRequest(accountId: firstID,
                address: "invalid", amount: "-1", memo: nil, sourcePools: 15, deductFee: false, confirmations: 0))
            preconditionFailure("Negative payment accepted")
        } catch {}
        let signed = try await wallet.signMessage(accountId: firstID, message: "Swift offline demo")
        try await wallet.verifyMessage(address: signed.address, message: "Swift offline demo", signature: signed.signature)
        do {
            try await wallet.verifyMessage(address: signed.address, message: "Changed message", signature: signed.signature)
            preconditionFailure("Altered signed message accepted")
        } catch {}
        model.recovery = nil
        let second = await model.addAccount(name: "Savings", key: nil, birth: 1)
        precondition(second && model.accounts.count == 2)
        try verifyReceivingCodes(model)
        let secondID = model.selectedAccountID!
        precondition(firstID != secondID)
        let renamed = await model.renameAccount(secondID, name: "Savings · Demo")
        precondition(renamed && model.selectedAccount?.name == "Savings · Demo")
        model.recovery = nil
        await model.selectAccount(firstID)
        precondition(model.selectedAccount?.name == "Main Wallet")
        precondition(model.overview != nil)
        precondition(WalletMoney.format("3.14012345") == "3.14012345")
        precondition(WalletMoney.format("0.00000001") == "0.00000001")
        await model.pollSyncStatus(forceTip: true)
        precondition(model.syncState == .offline, "An unreachable server must not show Synced")
        if CommandLine.arguments.count > 1 {
            try render(model, to: CommandLine.arguments[1])
            let outputRoot = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
            try render(model, to: outputRoot.appendingPathComponent("zkool-send-basic.png").path, screen: 1)
            try render(model, to: outputRoot.appendingPathComponent("zkool-send-advanced.png").path, screen: 2)
            try render(model, to: outputRoot.appendingPathComponent("zkool-receive.png").path, screen: 3)
            try render(model, to: outputRoot.appendingPathComponent("zkool-receive-expanded.png").path, screen: 4)
            try render(model, to: outputRoot.appendingPathComponent("zkool-message-tools.png").path, screen: 5)
            try render(model, to: outputRoot.appendingPathComponent("zkool-regtest-setup.png").path, screen: 6)
            let fixture = ["address": signed.address, "message": "Swift offline demo", "signature": signed.signature]
            try JSONSerialization.data(withJSONObject: fixture).write(to: outputRoot.appendingPathComponent("zkool-message-tools-fixture.json"))
            if let address = model.overview?.address.ua {
                try WalletReceiveQR(address: address).svg.write(
                    to: outputRoot.appendingPathComponent("zkool-receive.svg"), atomically: true, encoding: .utf8)
            }
        }
        await model.synchronizeSelected()
        precondition(model.syncState == .failed)
        precondition(!model.syncing)
        precondition(wallet.syncProgressHeight(accountId: firstID) == nil)
        print("SwiftUI wallet: fresh creation, backup, multi-account selection, exact amounts, and failed sync checks passed")
    }

    @MainActor
    static func verifyReceivingCodes(_ model: WalletModel) throws {
        let options = ReceivingAddress.options(model.overview?.address)
        precondition(!options.isEmpty)
        for option in options {
            precondition(!option.abbreviated.contains(option.value))
            let qr = try WalletReceiveQR(address: option.value)
            precondition(qr.svg.contains("viewBox=") && qr.svg.contains("<circle"))
            let parser = XMLParser(data: Data(qr.svg.utf8))
            parser.shouldResolveExternalEntities = false
            precondition(parser.parse(), "Receiving SVG must be valid XML")
            for side in [320, 640] {
                let image = qr.image(side: side)!
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                try VNImageRequestHandler(cgImage: image).perform([request])
                precondition(request.results?.contains { $0.payloadStringValue == option.value } == true,
                    "Branded receiving QR failed to decode at \(side)px for \(option.name)")
            }
        }
    }

    @MainActor
    static func render(_ model: WalletModel, to path: String, screen: Int = 0) throws {
        _ = NSApplication.shared
        let content: AnyView = screen == 6 ? AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Local regtest").font(.largeTitle.bold())
                    WalletConnectionFields(network: .constant(2), endpoint: .constant(WalletServerMode.localEndpoint(serverType: 0)), serverType: .constant(0))
                }.padding(24)
            }.background(WalletTheme.background).preferredColorScheme(.dark).tint(WalletTheme.green)) : screen == 5 ? AnyView(MessageToolsView()) : screen == 0 ? AnyView(WalletView()) :
            (screen >= 3 ? AnyView(ReceiveView(initiallyExpanded: screen == 4)) : AnyView(SendingView(initialAdvanced: screen == 2)))
        let height: CGFloat = screen == 2 ? 1150 : 1000
        let view = content.environmentObject(model).environment(\.scenePhase, .inactive)
            .frame(width: 420, height: height)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "WalletUISmoke", code: 1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WalletUISmoke", code: 2)
        }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
