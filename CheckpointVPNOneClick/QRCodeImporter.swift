import AppKit
import CoreImage
import Foundation
import Vision

enum QRCodeImporter {
    enum Error: Swift.Error, LocalizedError {
        case noImage
        case noQR
        case notTOTP

        var errorDescription: String? {
            switch self {
            case .noImage: return "Could not read that image."
            case .noQR: return "No QR code found in the image."
            case .notTOTP: return "QR is not a TOTP secret or otpauth:// link."
            }
        }
    }

    static func decode(image: NSImage) throws -> String {
        guard let cg = cgImage(from: image) else { throw Error.noImage }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])
        let payloads = (request.results ?? []).compactMap(\.payloadStringValue)
        guard let payload = payloads.first(where: { !$0.isEmpty }) else { throw Error.noQR }
        return try normalizedSecret(payload)
    }

    static func decode(fileURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: fileURL) else { throw Error.noImage }
        return try decode(image: image)
    }

    static func decodeClipboard() throws -> String {
        let pasteboard = NSPasteboard.general
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            return try decode(image: image)
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try normalizedSecret(text)
        }
        throw Error.noImage
    }

    static func normalizedSecret(_ payload: String) throws -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://") {
            _ = try TOTP.parseSecret(trimmed)
            return trimmed
        }
        if trimmed.lowercased().hasPrefix("otpauth-migration://") {
            throw Error.notTOTP
        }
        _ = try TOTP.parseSecret(trimmed)
        return trimmed
    }

    static func renderForTest(_ payload: String) -> NSImage? {
        guard let data = payload.data(using: .ascii),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
