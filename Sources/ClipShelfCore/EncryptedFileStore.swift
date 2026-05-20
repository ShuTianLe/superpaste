import CryptoKit
import Foundation

public final class EncryptedFileStore {
    public let baseURL: URL
    private let keyProvider: SymmetricKeyProviding
    private let fileManager: FileManager

    public init(
        baseURL: URL,
        keyProvider: SymmetricKeyProviding = KeychainKeyStore(),
        fileManager: FileManager = .default
    ) {
        self.baseURL = baseURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    public func prepare() throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: baseURL.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: baseURL.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
    }

    @discardableResult
    public func write(_ data: Data, folder: String = "blobs", extension ext: String = "bin") throws -> String {
        try prepare()
        let key = try keyProvider.loadOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw ClipShelfError.encryption("AES-GCM did not produce a combined representation")
        }

        let relativePath = "\(folder)/\(UUID().uuidString).\(ext)"
        let url = baseURL.appendingPathComponent(relativePath)
        try combined.write(to: url, options: [.atomic])
        return relativePath
    }

    public func read(relativePath: String) throws -> Data {
        let key = try keyProvider.loadOrCreateKey()
        let url = baseURL.appendingPathComponent(relativePath)
        let combined = try Data(contentsOf: url)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    public func delete(relativePath: String?) {
        guard let relativePath else {
            return
        }
        let url = baseURL.appendingPathComponent(relativePath)
        try? fileManager.removeItem(at: url)
    }
}
