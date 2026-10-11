import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ReceivingAddress: Identifiable {
    let id: String
    let name: String
    let value: String
    static func options(_ addresses: WalletAddresses?) -> [Self] {
        guard let addresses else { return [] }
        return [("main", "Main address", addresses.ua), ("orchard", "Orchard address", addresses.orchard),
                ("sapling", "Sapling address", addresses.sapling), ("transparent", "Transparent address", addresses.transparent)]
            .compactMap { id, name, value in
                guard let value, !value.isEmpty else { return nil }
                return Self(id: id, name: name, value: value)
            }
    }
    var abbreviated: String {
        func grouped(_ string: String) -> String {
            stride(from: 0, to: string.count, by: 4).map { index in
                let start = string.index(string.startIndex, offsetBy: index)
                let end = string.index(start, offsetBy: min(4, string.count - index))
                return String(string[start..<end])
            }.joined(separator: " ")
        }
        return value.count > 20 ? grouped(String(value.prefix(8))) + " … " + grouped(String(value.suffix(8))) : grouped(value)
    }
}

struct ReceiveView: View {
    @EnvironmentObject private var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection = "main"
    @State private var expanded = false
    @State private var copiedAddress: String?
    init(initiallyExpanded: Bool = false) { _expanded = State(initialValue: initiallyExpanded) }
    private var options: [ReceivingAddress] { ReceivingAddress.options(model.overview?.address) }
    private var selected: ReceivingAddress? { options.first { $0.id == selection } ?? options.first }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let reserved: CGFloat = model.message == nil ? 336 : 376
                let qrSide = min(440, geometry.size.width - 40, max(120, geometry.size.height - reserved))
                let qr = selected.flatMap { try? WalletReceiveQR(address: $0.value) }
                let inset = qr.map { qrSide * CGFloat(WalletReceiveQR.border) / $0.dimension } ?? 0
                content(qr: qr, qrSide: qrSide, inset: inset)
                    .frame(width: qrSide).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(WalletTheme.background)
            .walletNavigationChrome()
        }
        .tint(WalletTheme.green)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $expanded) {
            fullAddress
            #if os(iOS)
                .presentationDetents([.medium, .large])
            #endif
        }
    }

    private func content(qr: WalletReceiveQR?, qrSide: CGFloat, inset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.horizontal, inset)
            balance.padding(.horizontal, inset)
            receivingContent(qr: qr, qrSide: qrSide, inset: inset)
            if let message = model.message {
                Text(message).font(.footnote).foregroundStyle(WalletTheme.coral).lineLimit(2)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(model.selectedAccount?.name ?? "Receive Zcash").font(.headline).lineLimit(1).minimumScaleFactor(0.75)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").padding(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close receiving")
        }
    }

    @ViewBuilder
    private func receivingContent(qr: WalletReceiveQR?, qrSide: CGFloat, inset: CGFloat) -> some View {
        if let address = selected {
            if let qr {
                WalletReceiveQRView(qr: qr)
                    .frame(width: qrSide, height: qrSide)
                    .frame(maxWidth: .infinity)
                addressDetails(address).padding(.horizontal, inset)
                selector.padding(.horizontal, inset)
                actions(address, qr: qr).padding(.horizontal, inset)
            } else {
                Text("This address could not be encoded as a QR code.")
                    .foregroundStyle(WalletTheme.coral)
                addressDetails(address)
                selector
                ShareLink(item: address.value) { Text("Share address") }
                    .buttonStyle(WalletActionStyle(primary: true))
            }
        } else {
            Text("No receiving address is available for this account.")
                .foregroundStyle(Color.secondary)
        }
    }

    private func actions(_ address: ReceivingAddress, qr: WalletReceiveQR) -> some View {
        HStack(spacing: 12) {
            copyButton(address)
            shareMenu(address, qr: qr)
        }
    }

    private func copyButton(_ address: ReceivingAddress) -> some View {
        let copied = copiedAddress == address.value
        return Button { copy(address.value) } label: {
            Label(copied ? "Copied" : "Copy",
                  systemImage: copied ? "checkmark" : "doc.on.doc").frame(height: 18)
        }
        .buttonStyle(WalletActionStyle(primary: true))
        .accessibilityLabel("Copy receiving address")
    }

    private func shareMenu(_ address: ReceivingAddress, qr: WalletReceiveQR) -> some View {
        Menu {
            ShareLink(item: address.value) {
                Label("Share address", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: ReceivingSVG(svg: qr.svg),
                      preview: SharePreview("Zcash receiving QR", image: Image(systemName: "qrcode"))) {
                Label("Share QR as SVG", systemImage: "qrcode")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up").frame(height: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .walletActionSurface()
        .tint(Color.white)
    }

    private var balance: some View {
        let parts = WalletMoney.format(model.overview?.balance.total ?? "0").components(separatedBy: ".")
        let whole = parts.first ?? "—"
        let fraction = parts.count > 1 ? parts[1] : ""
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(whole + "." + String(fraction.prefix(3))).font(WalletFont.numbers(42, bold: true))
            Text(String(fraction.dropFirst(3))).font(WalletFont.numbers(17, bold: true))
            Text("ZEC").font(WalletFont.numbers(17, bold: true)).padding(.leading, 5)
        }.lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Account balance \(WalletMoney.format(model.overview?.balance.total ?? "0")) ZEC")
    }

    private func addressDetails(_ address: ReceivingAddress) -> some View {
        VStack(spacing: 16) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Text(address.abbreviated).font(WalletFont.numbers(17, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.plain).foregroundStyle(Color.white)
                .accessibilityLabel(expanded ? "Collapse full address" : "Show full address")
        }
    }

    private var fullAddress: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Receiving address").font(.title2.bold())
                        Spacer()
                        Button { expanded = false } label: { Image(systemName: "xmark").padding(10) }
                            .buttonStyle(.plain).accessibilityLabel("Close full address")
                    }
                    if let address = selected {
                        Text(address.value).font(WalletFont.numbers(14)).textSelection(.enabled)
                        copyButton(address)
                    }
                    Text("Previous addresses still receive funds into this account.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                }.padding(24)
            }.background(WalletTheme.background).walletNavigationChrome()
        }.tint(WalletTheme.green).preferredColorScheme(.dark)
    }

    private var selector: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.id
                    expanded = false
                    copiedAddress = nil
                } label: {
                    if selected?.id == option.id { Label(option.name, systemImage: "checkmark") }
                    else { Text(option.name) }
                }
            }
            Divider()
            Button {
                Task {
                    if await model.newReceiveAddress() {
                        selection = "main"
                        expanded = false
                        copiedAddress = nil
                    }
                }
            } label: { Label("New receive address", systemImage: "arrow.triangle.2.circlepath") }
                .disabled(model.busy)
        } label: {
            HStack { Text(selected?.name ?? "Address"); Image(systemName: "chevron.down") }
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
            .walletActionSurface().tint(Color.white)
            .accessibilityLabel("Receiving address type: \(selected?.name ?? "None")")
    }

    private func copy(_ address: String) {
        #if os(iOS)
        UIPasteboard.general.string = address
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        #endif
        copiedAddress = address
    }
}
