import Foundation

public struct PrivacyEntry: Codable, Sendable {
    public var date: Date
    public var task: String
    public var model: String
    public var sentText: String
    public init(date: Date, task: String, model: String, sentText: String) {
        self.date = date; self.task = task; self.model = model; self.sentText = sentText
    }
}

/// Every cloud request, persisted as JSON. Only text is ever recorded because only text is ever sent.
public final class PrivacyLog: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    public private(set) var entries: [PrivacyEntry]
    public var photosUploaded: Int { 0 }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        entries = (try? JSONDecoder().decode([PrivacyEntry].self, from: Data(contentsOf: fileURL))) ?? []
    }

    public func append(_ e: PrivacyEntry) {
        lock.lock(); defer { lock.unlock() }
        entries.append(e)
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
