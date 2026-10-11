import SwiftUI
import QRCodeGenerator
import CoreTransferable
import UniformTypeIdentifiers

// The library encodes the full address. Display paths and SVG use that same matrix.
struct WalletReceiveQR {
    let code: QRCode
    static let border = 4
    static let backgroundHex = "#0b1213"
    var dimension: CGFloat { CGFloat(code.size + Self.border * 2) }
    var center: CGFloat { dimension / 2 }
    // Odd module count keeps every cutout edge on an integer QR-grid boundary.
    var maskModules: Int { max(5, Int(CGFloat(code.size) * 0.20) | 1) }
    var badgeSide: CGFloat { CGFloat(maskModules - 2) }
    init(address: String) throws { code = try QRCode.encode(text: address, ecl: .high) }

    var modules: Path {
        var path = Path()
        for y in 0..<code.size {
            for x in 0..<code.size where code.getModule(x: x, y: y) {
                path.addRect(CGRect(x: x + Self.border, y: y + Self.border, width: 1, height: 1))
            }
        }
        return path
    }
    var mask: CGRect {
        let side = CGFloat(maskModules)
        return CGRect(x: center - side / 2, y: center - side / 2, width: side, height: side)
    }
    var badge: Path {
        ZcashBadge.path.applying(CGAffineTransform(a: badgeSide / 53, b: 0, c: 0, d: badgeSide / 53,
            tx: center - badgeSide / 2, ty: center - badgeSide / 2))
    }
    var svg: String {
        let base = code.toSVGString(border: Self.border, foreground: "#ffffff", background: Self.backgroundHex)
            .replacingOccurrences(of: "stroke=\"none\">", with: "width=\"1024\" height=\"1024\" stroke=\"none\">")
        let badge = """
          <rect x="\(mask.minX)" y="\(mask.minY)" width="\(mask.width)" height="\(mask.height)" fill="\(Self.backgroundHex)"/>
          <path transform="translate(\(center - badgeSide / 2) \(center - badgeSide / 2)) scale(\(badgeSide / 53))"
                d="\(ZcashBadge.svgPath)" fill="#ffffff" fill-rule="evenodd" clip-rule="evenodd"/>
        </svg>
        """
        return base.replacingOccurrences(of: "</svg>", with: badge)
    }

    // Used to verify that the branded vector still decodes to the original address.
    func image(side: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.045, green: 0.07, blue: 0.075, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: CGFloat(side) / dimension, y: -CGFloat(side) / dimension)
        context.setShouldAntialias(false)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.addPath(modules.cgPath); context.fillPath()
        context.setFillColor(CGColor(red: 0.045, green: 0.07, blue: 0.075, alpha: 1)); context.fill(mask)
        context.setShouldAntialias(true)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.addPath(badge.cgPath); context.drawPath(using: .eoFill)
        return context.makeImage()
    }
}

// Exact badge supplied in the receive reference: white disc with a Z-shaped cutout.
private enum ZcashBadge {
    static let svgPath = "M0 26.4731C0 11.8737 11.8737 0 26.4731 0C41.0725 0 52.9461 11.8737 52.9461 26.4731C52.9461 41.0725 41.0725 52.9461 26.4731 52.9461C11.8737 52.9461 0 41.0725 0 26.4731ZM35.9161 14.1876V18.2164L24.7111 33.4139H35.9161V38.7575H28.6929V43.1854H24.2532V38.7575H17.03V34.7287L28.2232 19.5312H17.03V14.1876H24.2532V9.74797H28.6929V14.1876H35.9161Z"
    static var path: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 26.4731))
        path.addCurve(to: CGPoint(x: 26.4731, y: 0), control1: CGPoint(x: 0, y: 11.8737), control2: CGPoint(x: 11.8737, y: 0))
        path.addCurve(to: CGPoint(x: 52.9461, y: 26.4731), control1: CGPoint(x: 41.0725, y: 0), control2: CGPoint(x: 52.9461, y: 11.8737))
        path.addCurve(to: CGPoint(x: 26.4731, y: 52.9461), control1: CGPoint(x: 52.9461, y: 41.0725), control2: CGPoint(x: 41.0725, y: 52.9461))
        path.addCurve(to: CGPoint(x: 0, y: 26.4731), control1: CGPoint(x: 11.8737, y: 52.9461), control2: CGPoint(x: 0, y: 41.0725))
        path.closeSubpath()
        path.move(to: CGPoint(x: 35.9161, y: 14.1876))
        for (x, y) in [(35.9161, 18.2164), (24.7111, 33.4139), (35.9161, 33.4139), (35.9161, 38.7575),
                       (28.6929, 38.7575), (28.6929, 43.1854), (24.2532, 43.1854), (24.2532, 38.7575),
                       (17.03, 38.7575), (17.03, 34.7287), (28.2232, 19.5312), (17.03, 19.5312),
                       (17.03, 14.1876), (24.2532, 14.1876), (24.2532, 9.74797), (28.6929, 9.74797),
                       (28.6929, 14.1876)] { path.addLine(to: CGPoint(x: x, y: y)) }
        path.closeSubpath()
        return path
    }
}

struct WalletReceiveQRView: View {
    let qr: WalletReceiveQR
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / qr.dimension
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            ZStack(alignment: .topLeading) {
                WalletTheme.background
                qr.modules.applying(transform).fill(.white, style: FillStyle(antialiased: false))
                Path(qr.mask).applying(transform).fill(WalletTheme.background, style: FillStyle(antialiased: false))
                qr.badge.applying(transform).fill(Color.white, style: FillStyle(eoFill: true))
            }
        }.aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore).accessibilityLabel("Receiving address QR code")
    }
}

struct ReceivingSVG: Transferable {
    let svg: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .svg) { Data($0.svg.utf8) }
            .suggestedFileName("Zkool-receiving-address.svg")
    }
}
