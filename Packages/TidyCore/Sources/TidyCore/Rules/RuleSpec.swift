import Foundation

public struct RuleSpec: Codable, Equatable, Sendable {
    public struct Filter: Codable, Equatable, Sendable {
        public var kinds: [Kind]?
        public var junkTypes: [JunkType]?
        public var docTypes: [DocType]?
        public var keywords: [String]?
        /// Things seen in the photo (Vision labels such as dog, beach, food).
        public var labels: [String]?
        public var sources: [String]?
        public var dateFrom: Date?
        public var dateTo: Date?
        enum CodingKeys: String, CodingKey {
            case kinds, keywords, sources, labels
            case junkTypes = "junk_types", docTypes = "doc_types", dateFrom = "date_from", dateTo = "date_to"
        }
        public init(kinds: [Kind]? = nil, junkTypes: [JunkType]? = nil, docTypes: [DocType]? = nil, keywords: [String]? = nil, labels: [String]? = nil,
                    sources: [String]? = nil, dateFrom: Date? = nil, dateTo: Date? = nil) {
            self.kinds = kinds; self.junkTypes = junkTypes; self.docTypes = docTypes; self.keywords = keywords; self.labels = labels
            self.sources = sources; self.dateFrom = dateFrom; self.dateTo = dateTo
        }
        public var isEmpty: Bool { kinds == nil && junkTypes == nil && docTypes == nil && keywords == nil && labels == nil && sources == nil && dateFrom == nil && dateTo == nil }
    }
    public var name: String
    public var include: Filter
    public var exclude: Filter?
    /// How the photos look, for on-device picture search ("a girl in a red dress"). Optional; labels are the fallback.
    public var visual: String?
    public init(name: String, include: Filter, exclude: Filter? = nil) { self.name = name; self.include = include; self.exclude = exclude }
}
