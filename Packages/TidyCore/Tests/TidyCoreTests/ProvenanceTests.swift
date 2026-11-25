import Testing
@testable import TidyCore

@Test func iptcTrainedMedia() {
    let p = ProvenanceInput(digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia")
    #expect(aiMadeSource(p) == "Marked as AI-generated (IPTC)")
}
@Test func iptcCompositeTrainedMedia() {
    let p = ProvenanceInput(digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia")
    #expect(aiMadeSource(p) == "Marked as AI-generated (IPTC)")
}
@Test func softwareChatGPT() { #expect(aiMadeSource(ProvenanceInput(software: "ChatGPT")) == "Made with ChatGPT") }
@Test func creatorToolMidjourney() { #expect(aiMadeSource(ProvenanceInput(creatorTool: "Midjourney v7")) == "Made with Midjourney") }
@Test func imagePlayground() { #expect(aiMadeSource(ProvenanceInput(software: "Image Playground")) == "Made with Image Playground") }
@Test func c2paOnlyFallback() { #expect(aiMadeSource(ProvenanceInput(hasC2PA: true)) == "Has AI Content Credentials") }
@Test func cameraPhotoIsNil() { #expect(aiMadeSource(ProvenanceInput(software: "26.6")) == nil) }
