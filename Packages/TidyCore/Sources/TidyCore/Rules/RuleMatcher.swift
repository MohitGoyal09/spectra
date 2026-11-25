import Foundation

/// Per field: nil = no condition. All present fields must hold; within a field any value may match.
private func fieldHits(_ f: RuleSpec.Filter, _ v: Verdict, _ r: PhotoRecord) -> [Bool] {
    var hits: [Bool] = []
    if let k = f.kinds { hits.append(k.contains(v.kind)) }
    if let j = f.junkTypes { hits.append(v.junkType.map(j.contains) ?? false) }
    if let d = f.docTypes { hits.append(v.docType.map(d.contains) ?? false) }
    if let words = f.keywords { hits.append(words.contains { textHas(r.ocrText, $0) || textHas(r.place ?? "", $0) || showsThing($0, r) }) }
    if let l = f.labels { hits.append(l.contains { showsThing($0, r) }) }
    if let s = f.sources { hits.append(r.sourceAlbums.contains { a in s.contains { a.localizedCaseInsensitiveContains($0) } }) }
    if let from = f.dateFrom { hits.append(r.createdAt >= from) }
    if let to = f.dateTo { hits.append(r.createdAt <= to) }
    return hits
}

/// `visual`: whether picture search found this photo for `rule.visual` (nil when picture search is off).
/// With picture search, kinds/dates/types must still hold, and the photo must either look right or have the words written in it.
public func matches(_ rule: RuleSpec, verdict v: Verdict, record r: PhotoRecord, visual: Bool? = nil) -> Bool {
    guard v.sensitive == nil else { return false }
    if rule.visual != nil, let visual {
        var structure = rule.include; structure.keywords = nil; structure.labels = nil
        guard fieldHits(structure, v, r).allSatisfy({ $0 }) else { return false }
        let written = rule.include.keywords?.contains { textHas(r.ocrText, $0) || textHas(r.place ?? "", $0) } ?? false
        guard visual || written else { return false }
    } else {
        guard !rule.include.isEmpty, fieldHits(rule.include, v, r).allSatisfy({ $0 }) else { return false }
    }
    if let ex = rule.exclude, !ex.isEmpty, fieldHits(ex, v, r).contains(true) { return false }
    return true
}

/// Simple English stem: lowercased, trailing plural "s"/"es" dropped ("receipts" → "receipt", "dogs" → "dog").
func stem(_ word: String) -> String {
    let w = word.lowercased()
    guard w.count > 3 else { return w }
    if w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
    if w.hasSuffix("ses") || w.hasSuffix("xes") || w.hasSuffix("ches") || w.hasSuffix("shes") { return String(w.dropLast(2)) }
    if w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast()) }
    return w
}

/// A wanted label matches a Vision identifier on any word: "sunset" matches "sunset_sunrise", "dogs" matches "dog".
func labelMatches(_ want: String, _ label: String) -> Bool {
    let w = stem(want.replacingOccurrences(of: "_", with: " "))
    let words = label.lowercased().split(separator: "_").map { stem(String($0)) }
    return words.contains(w) || label.lowercased().replacingOccurrences(of: "_", with: " ") == w
}

/// Everyday words → the Vision labels that show them. Vision does not guess gender or age, so people words map to "people".
let labelSynonyms: [String: [String]] = {
    var m: [String: [String]] = [:]
    func add(_ words: [String], _ labels: [String]) { for w in words { m[stem(w)] = labels } }
    add(["girl", "boy", "woman", "women", "man", "men", "lady", "ladies", "guy", "friend", "family", "person", "people", "selfie", "me", "kid", "child", "children", "baby", "portrait"],
        ["people", "adult", "child", "baby", "portrait"])
    add(["lens", "lenses", "glasses", "spectacle", "specs", "sunglass", "eyewear", "frame"], ["eyeglasses", "sunglasses", "optical_equipment"])
    add(["puppy", "puppies", "doggo"], ["dog", "puppy"])
    add(["kitten", "kitty"], ["cat", "kitten"])
    add(["pet"], ["dog", "cat", "animal", "bird"])
    add(["car", "cars", "vehicle"], ["car", "automobile", "vehicle"])
    add(["bike", "motorbike", "motorcycle", "scooter"], ["motorcycle", "bicycle", "scooter"])
    add(["food", "meal", "dinner", "lunch", "breakfast", "dish"], ["food", "meal", "dish", "dessert", "baked_goods", "fruit", "vegetable"])
    add(["beach", "sea", "ocean"], ["beach", "sea", "ocean", "shore", "coast"])
    add(["mountain", "hill", "trek"], ["mountain", "hill", "cliff", "volcano"])
    add(["sunset", "sunrise"], ["sunset_sunrise"])
    add(["flower"], ["flower", "blossom", "rose"])
    add(["cake", "birthday"], ["cake", "birthday_cake", "candle"])
    add(["watch", "smartwatch"], ["watch", "wristwatch", "timepiece", "dial"])
    add(["night"], ["night_sky", "night"])
    return m
}()

public enum MatchConfig {
    /// Below this Vision confidence a label is a guess, not a fact; it can rank a result but never match one.
    public static let minLabelScore: Float = 0.25
}

/// Labels this photo confidently shows, with scores (old index entries: top labels, scored 1).
func confidentLabels(_ r: PhotoRecord) -> [String: Float] {
    r.labelScores?.filter { $0.value >= MatchConfig.minLabelScore } ?? Dictionary(r.labels.map { ($0, 1) }, uniquingKeysWith: max)
}

/// Best confidence with which the labels show this thing: the word itself ("dog") or what it means ("girls" → people).
func labelScore(_ word: String, _ labels: [String: Float]) -> Float? {
    let wants = (labelSynonyms[stem(word)] ?? []) + [word]
    return labels.filter { l, _ in wants.contains { labelMatches($0, l) } }.values.max()
}

func showsThing(_ word: String, _ r: PhotoRecord) -> Bool { labelScore(word, confidentLabels(r)) != nil }

/// Ranking for a rule's matches: written words count 1, labels count their confidence.
public func relevance(_ rule: RuleSpec, record r: PhotoRecord) -> Float {
    let labels = confidentLabels(r)
    let words = (rule.include.keywords ?? []).map { textHas(r.ocrText, $0) ? 1 : labelScore($0, labels) ?? 0 }
    return (words + (rule.include.labels ?? []).map { labelScore($0, labels) ?? 0 }).reduce(0, +)
}

/// A text word starts with the query word; only for words of 4+ letters ("lens" → "lenskart", but "red" ✗ "redis").
func startsWord(_ token: some StringProtocol, _ w: String) -> Bool { token == w || (w.count >= 4 && token.hasPrefix(w)) }

/// Whole-word match: a word in the text starts with the query word ("lens" → "lenskart") or is its plural/singular.
/// Never matches inside a word ("lens" ✗ "challenges").
func textHas(_ text: String, _ word: String) -> Bool {
    let w = word.lowercased()
    if w.contains(" ") { return text.lowercased().contains(w) }
    let s = stem(w)
    return text.lowercased().split { !$0.isLetter && !$0.isNumber }.contains { startsWord($0, w) || stem(String($0)) == s }
}

/// Search: every query word must match the text as a whole word or through a label it implies, in any order.
public func searchMatches(_ query: String, in text: String) -> Bool { searchScore(query, text: text, labelScores: [:]) != nil }

/// Search score: nil unless every word matches. Each word scores 1 for written text, else the confidence of the label that shows it.
/// Labels in `text` without a score count 0.5.
public func searchScore(_ query: String, text: String, labelScores: [String: Float]) -> Float? {
    let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    guard !words.isEmpty else { return nil }
    let hay = text.lowercased().replacingOccurrences(of: "_", with: " ")
    let tokens = hay.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    let confident = labelScores.filter { $0.value >= MatchConfig.minLabelScore }
    var total: Float = 0
    for w in words {
        let s = stem(w)
        if let l = labelScore(w, confident) { total += max(l, tokens.contains(where: { startsWord($0, w) || stem($0) == s }) ? 1 : 0); continue }
        if tokens.contains(where: { startsWord($0, w) || stem($0) == s }) { total += 1; continue }
        if (labelSynonyms[s] ?? []).contains(where: { hay.contains($0.replacingOccurrences(of: "_", with: " ")) }) { total += 0.5; continue }
        return nil
    }
    return total
}

/// Picture search: which photos stand out for a query. Keeps similarities well above this library's usual level
/// (mean + `z` standard deviations) and above an absolute `floor`; best first.
public func clipPick(_ sims: [Float], floor: Float = 0.21, z: Float = 2.5, limit: Int = 300) -> [Int] {
    guard sims.count > 1 else { return sims.first.map { $0 >= floor ? [0] : [] } ?? [] }
    let mean = sims.reduce(0, +) / Float(sims.count)
    let std = (sims.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(sims.count)).squareRoot()
    let cut = max(floor, mean + z * std)
    return sims.indices.filter { sims[$0] >= cut }.sorted { sims[$0] > sims[$1] }.prefix(limit).map { $0 }
}
