import Foundation
import SwiftUI

struct WalletConnection: Equatable {
    let network: UInt8
    let serverType: UInt8
    let endpoint: String
    var networkName: String { ["Mainnet", "Testnet", "Regtest", "ZSA regtest"][Int(min(network, 3))] }
    var backendName: String { serverType == 0 ? "Lightwalletd" : "Zebra RPC" }
}

enum WalletServerMode: String, CaseIterable, Identifiable {
    case publicServer = "Public server", localRegtest = "Local regtest", custom = "Custom server"
    var id: String { rawValue }
    static func localEndpoint(serverType: UInt8) -> String {
        serverType == 0 ? "http://127.0.0.1:8137" : "http://127.0.0.1:18232"
    }
}

struct WalletConnectionFields: View {
    @Binding var network: UInt8
    @Binding var endpoint: String
    @Binding var serverType: UInt8
    @State private var mode = WalletServerMode.publicServer

    init(network: Binding<UInt8>, endpoint: Binding<String>, serverType: Binding<UInt8>) {
        _network = network
        _endpoint = endpoint
        _serverType = serverType
        let initial: WalletServerMode = network.wrappedValue >= 2 ? .localRegtest :
            (network.wrappedValue == 0 && endpoint.wrappedValue == "https://zec.rocks" && serverType.wrappedValue == 0 ? .publicServer : .custom)
        _mode = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Server mode", selection: $mode) {
                ForEach(WalletServerMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            Picker("Network", selection: $network) {
                Text("Mainnet").tag(UInt8(0))
                Text("Testnet").tag(UInt8(1))
                Text("Regtest").tag(UInt8(2))
                Text("ZSA regtest").tag(UInt8(3))
            }
            Picker("Backend", selection: $serverType) {
                Text("Lightwalletd (gRPC)").tag(UInt8(0))
                Text("Zebra (JSON-RPC)").tag(UInt8(1))
            }.disabled(mode == .publicServer)
            TextField("Server URL", text: $endpoint).walletInput(url: true)
                .accessibilityLabel("Server URL")
            if mode == .localRegtest {
                Text("Simulator: 127.0.0.1 connects to your Mac. On an iPhone, enter the server computer’s LAN address and expose the selected port to your local network.")
                    .font(.footnote).foregroundStyle(Color.secondary)
                Text("Local defaults: lightwalletd 8137 · Zebra RPC 18232. Choose Regtest or ZSA regtest to match your node.")
                    .font(.footnote).foregroundStyle(Color.secondary)
                Button("Reset local server URL") { endpoint = WalletServerMode.localEndpoint(serverType: serverType) }
                    .buttonStyle(WalletActionStyle())
            }
        }
        .onChange(of: mode) { selected in
            if selected == .localRegtest {
                if network < 2 { network = 2 }
                endpoint = WalletServerMode.localEndpoint(serverType: serverType)
            } else if selected == .publicServer {
                network = 0
                serverType = 0
                endpoint = "https://zec.rocks"
            }
        }
        .onChange(of: network) { selected in
            if selected >= 2 && mode != .localRegtest {
                mode = .localRegtest
            } else if selected < 2 && mode == .localRegtest {
                mode = .custom
            } else if selected == 1 && mode == .publicServer {
                mode = .custom
                endpoint = ""
            }
        }
        .onChange(of: serverType) { selected in
            if mode == .localRegtest { endpoint = WalletServerMode.localEndpoint(serverType: selected) }
        }
    }
}
