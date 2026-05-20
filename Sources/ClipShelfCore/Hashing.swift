import CryptoKit
import Foundation

public enum Hashing {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func contentHash(payloads: [ClipboardPayload]) -> String {
        var combined = Data()
        for payload in payloads.sorted(by: { $0.uti < $1.uti }) {
            combined.append(payload.uti.data(using: .utf8) ?? Data())
            combined.append(0)
            combined.append(SHA256.hash(data: payload.data).data)
            combined.append(0)
        }
        return sha256Hex(combined)
    }
}

private extension SHA256.Digest {
    var data: Data {
        Data(self)
    }
}
