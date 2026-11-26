#if os(iOS)
import CoreML
import Foundation

/// A single serial inference context, shared by the settings preview and the conversation.
actor KokoroVoiceEngine {
    static let shared = KokoroVoiceEngine()
    private var loaded: KokoroFrenchGraph?

    func synthesize(_ text: String) throws -> [Float] {
        try Task.checkCancellation()
        guard let directory = NoctisVoiceModel.installedDirectory else {
            loaded = nil
            throw CocoaError(.fileNoSuchFile)
        }
        if loaded == nil { loaded = try KokoroFrenchGraph(directory: directory) }
        guard let loaded else { throw CocoaError(.fileReadCorruptFile) }
        return try loaded.render(text)
    }
}

private struct KokoroFrenchGraph {
    let model: MLModel
    let textProcessor: KokoroFrenchText
    let style: MLMultiArray

    init(directory: URL) throws {
        let decoder = JSONDecoder()
        struct Vocabulary: Decodable { let vocab: [String: Int32] }
        struct Voice: Decodable { let embedding: [Float] }
        let vocabFile = directory.appending(path: "vocab_index.json")
        let voiceFile = directory.appending(path: "voices/ff_siwis.json")
        let vocab = try decoder.decode(Vocabulary.self, from: Data(contentsOf: vocabFile))
        let voice = try decoder.decode(Voice.self, from: Data(contentsOf: voiceFile))
        guard voice.embedding.count >= 256, let lexiconFile = Bundle.main.url(
            forResource: "KokoroFrenchLexicon", withExtension: "json"
        ) else { throw CocoaError(.fileReadCorruptFile) }
        let lexicon = try decoder.decode([String: String].self, from: Data(contentsOf: lexiconFile))
        textProcessor = KokoroFrenchText(lexicon: lexicon, vocabulary: vocab.vocab)
        style = try MLMultiArray(shape: [1, 256], dataType: .float32)
        for index in 0..<256 { style[index] = NSNumber(value: voice.embedding[index]) }
        let configuration = MLModelConfiguration()
        // The GPU compiler can abort the process in MPSReorderOperations for this Kokoro graph.
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: directory.appending(path: "kokoro_5s.mlmodelc"), configuration: configuration)
    }

    func render(_ text: String) throws -> [Float] {
        let phonemes = textProcessor.tokens(for: text)
        let space = textProcessor.vocabulary[" "]
        var remainder = phonemes[...]
        var audio: [Float] = []
        while !remainder.isEmpty {
            try Task.checkCancellation()
            // Keep most phrases well inside the five-second graph. Split long words as a last resort.
            let window = remainder.prefix(52)
            let end = window.endIndex < remainder.endIndex
                ? Self.breakPoint(window, space: space) : window.endIndex
            let piece = try renderPhrase(remainder[..<end], space: space)
            audio.append(contentsOf: piece)
            remainder = remainder[end...]
        }
        return audio
    }

    private static func breakPoint(_ tokens: ArraySlice<Int32>, space: Int32?) -> Int {
        if let space, let boundary = tokens.dropFirst(tokens.count / 2).lastIndex(of: space) { return boundary + 1 }
        return tokens.endIndex
    }

    private func renderPhrase(_ phrase: ArraySlice<Int32>, space: Int32?) throws -> [Float] {
        try Task.checkCancellation()
        // hexgrad's KModel.forward uses ID 0 for both utterance boundaries.
        // The mask keeps those slots active and masks only the zero padding.
        let framed = [Int32(0)] + phrase + [Int32(0)]
        let ids = try MLMultiArray(shape: [1, 128], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, 128], dataType: .int32)
        for index in 0..<128 {
            let active = index < framed.count
            ids[index] = NSNumber(value: active ? framed[index] : 0)
            mask[index] = NSNumber(value: active ? 1 : 0)
        }
        let phases = try MLMultiArray(shape: [1, 9], dataType: .float32)
        for index in 0..<9 { phases[index] = NSNumber(value: Float.random(in: 0..<1)) }
        let speed = try MLMultiArray(shape: [1], dataType: .float32)
        speed[0] = 1
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": ids, "attention_mask": mask, "ref_s": style,
            "speed": speed, "random_phases": phases
        ])
        let output = try model.prediction(from: input)
        try Task.checkCancellation()
        guard let pcm = output.featureValue(for: "audio")?.multiArrayValue,
              let length = output.featureValue(for: "audio_length_samples")?.multiArrayValue,
              pcm.dataType == .float32, length.count > 0, pcm.strides.last?.intValue == 1
        else { throw CocoaError(.fileReadCorruptFile) }
        let count = min(pcm.count, max(0, length[0].intValue))
        if count > pcm.count - 4_800, phrase.count > 8 {
            // When the model predicts more speech than the fixed output window, re-render both halves.
            let middle = Self.breakPoint(phrase.prefix(phrase.count / 2), space: space)
            return try renderPhrase(phrase[..<middle], space: space) + renderPhrase(phrase[middle...], space: space)
        }
        let samples = pcm.dataPointer.assumingMemoryBound(to: Float.self)
        var audio = UnsafeBufferPointer(start: samples, count: count).map { min(1, max(-1, $0)) }
        let fade = min(120, count / 2)
        for index in 0..<fade {
            let gain = Float(index) / Float(fade)
            audio[index] *= gain
            audio[count - 1 - index] *= gain
        }
        return audio
    }
}
#endif
