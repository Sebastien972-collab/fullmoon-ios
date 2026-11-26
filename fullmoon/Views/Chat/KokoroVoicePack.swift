#if os(iOS)
import CryptoKit
import Foundation

enum KokoroVoicePack {
    static let revision = "4ef656f55554ceb242ed11febbdbbffd60dd5938"
    private static let repository = "aufklarer/Kokoro-82M-CoreML-INT8"
    private static let graph = "kokoro_5s.mlmodelc"
    private static let paths = [
        "vocab_index.json", "voices/ff_siwis.json",
        graph + "/coremldata.bin", graph + "/analytics/coremldata.bin", graph + "/model.mil",
        graph + "/weights/weight.bin"
    ]
    private static let weightHash = "2dfc4610bdac87159e33e6f3d3c011c110928f89916d9a59621eff48e7523c6a"
    private static let root = URL.applicationSupportDirectory
        .appending(path: "NoctisVoices", directoryHint: .isDirectory)
    private static let destination = root.appending(path: revision, directoryHint: .isDirectory)
    private static let receipt = "installed.json"

    struct LFS: Decodable {
        let oid: String
    }

    struct Entry: Decodable {
        let path: String
        let size: Int64
        let oid: String
        let lfs: LFS?
    }

    // The receipt is written only after every blob passes verification. A launch
    // or offline read checks for truncated/missing files without rehashing 84 MB.
    static var installedDirectory: URL? {
        guard let data = try? Data(contentsOf: destination.appending(path: receipt)),
              let sizes = try? JSONDecoder().decode([String: Int64].self, from: data),
              Set(sizes.keys) == Set(paths) else { return nil }
        for (path, expectedBytes) in sizes {
            guard let size = try? destination.appending(path: path).resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  expectedBytes > 0, Int64(size) == expectedBytes else { return nil }
        }
        return destination
    }

    static func discardAbandonedStaging() {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.lastPathComponent.hasPrefix("staging-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Runs off the UI actor. Failed or cancelled tasks remove their own staging directory.
    static func stage(id: UUID, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let entries = try await fetchEntries()
        let total = entries.reduce(Int64.zero) { $0 + $1.size }
        var directory = root
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let staged = directory.appending(path: "staging-" + id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        do {
            var completed: Int64 = 0
            for entry in entries {
                try Task.checkCancellation()
                let previous = completed
                try await download(entry, to: staged) { written in
                    progress(Double(previous + min(written, entry.size)) / Double(total))
                }
                completed += entry.size
                progress(Double(completed) / Double(total))
            }
            let sizes = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.size) })
            try JSONEncoder().encode(sizes).write(to: staged.appending(path: receipt), options: .atomic)
            return staged
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    static func install(_ staged: URL) throws {
        if installedDirectory != nil { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: staged, to: destination)
    }

    private static func fetchEntries() async throws -> [Entry] {
        let address = "https://huggingface.co/api/models/" + repository + "/tree/" + revision + "?recursive=true"
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        try requireSuccess(response)
        let tree = try JSONDecoder().decode([Entry].self, from: data)
        return try paths.map { path in
            guard let entry = tree.first(where: { $0.path == path }), (1...90_000_000).contains(entry.size),
                  entry.oid.count == 40 else { throw URLError(.cannotParseResponse) }
            if path.hasSuffix("/weights/weight.bin"), entry.lfs?.oid != weightHash {
                throw URLError(.cannotDecodeRawData)
            }
            return entry
        }
    }

    private static func download(
        _ entry: Entry, to directory: URL, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let address = "https://huggingface.co/" + repository + "/resolve/" + revision + "/" + entry.path
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        let delegate = VoiceDownloadProgress(report: progress)
        let (temp, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temp) }
        try Task.checkCancellation()
        try requireSuccess(response)
        try verify(temp, entry: entry)
        let target = directory.appending(path: entry.path)
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temp, to: target)
    }

    private static func requireSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    static func verify(_ file: URL, entry: Entry) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size.map(Int64.init) == entry.size else { throw URLError(.cannotDecodeRawData) }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest: [UInt8]
        let expected: String
        if let lfs = entry.lfs {
            digest = Array(SHA256.hash(data: data))
            expected = lfs.oid
        } else {
            // HF regular files use Git's SHA-1 over the blob header and contents.
            var hash = Insecure.SHA1()
            hash.update(data: Data("blob \(entry.size)\0".utf8))
            hash.update(data: data)
            digest = Array(hash.finalize())
            expected = entry.oid
        }
        guard digest.map({ String(format: "%02x", $0) }).joined() == expected else {
            throw URLError(.cannotDecodeRawData)
        }
    }
}

private final class VoiceDownloadProgress: NSObject, URLSessionDownloadDelegate {
    let report: @Sendable (Int64) -> Void

    init(report: @escaping @Sendable (Int64) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
#endif
