/// Human-readable source when file metadata says an image was AI-generated; nil otherwise.
/// Metadata only: images whose metadata was stripped (e.g. WhatsApp forwards) are not detected.
public func aiMadeSource(_ p: ProvenanceInput) -> String? {
    if let dst = p.digitalSourceType?.lowercased(), dst.hasSuffix("trainedalgorithmicmedia") {
        return "Marked as AI-generated (IPTC)"
    }
    let tools = [p.software, p.creatorTool].compactMap { $0?.lowercased() }.joined(separator: " ")
    let known: [(keys: [String], label: String)] = [
        (["chatgpt", "openai", "dall"], "Made with ChatGPT"),
        (["midjourney"], "Made with Midjourney"),
        (["image playground"], "Made with Image Playground"),
        (["firefly"], "Made with Adobe Firefly"),
        (["gemini", "imagen"], "Made with Google AI"),
        (["stable diffusion"], "Made with Stable Diffusion"),
    ]
    if let hit = known.first(where: { $0.keys.contains { tools.contains($0) } }) { return hit.label }
    return p.hasC2PA ? "Has AI Content Credentials" : nil
}
