import Foundation
#if canImport(llama)
internal import llama
#endif

/// Sampling and length settings for one generation.
struct LLMGenerationOptions: Sendable, Equatable {
    var maxTokens = 320
    var temperature: Float = 0.75
    var topK: Int32 = 20
    var topP: Float = 0.9
    var minP: Float = 0.02
    var repeatPenalty: Float = 1.08
    var presencePenalty: Float = 0.3
    var penaltyLastN: Int32 = 96
    var seed: UInt32 = 0xDEA5_EA27
    /// Generation stops as soon as any of these appear (the marker itself is not emitted).
    var stopSequences: [String] = ["<|im_end|>", "<|im_start|>", "<|endoftext|>", "\nUser:", "\n用户："]
    /// Ends the turn cleanly (as if the model had finished) after this many complete sentences.
    var maxSentences: Int?
}

enum SentenceCounter {
    /// Sentence ends followed by more text ("Hi. How" counts one; a trailing "." waits for what follows).
    static func complete(in text: String) -> Int {
        var count = 0
        var previousWasEnd = false
        for ch in text {
            if "。！？".contains(ch) { count += 1; previousWasEnd = false; continue }
            if ".!?".contains(ch) { previousWasEnd = true; continue }
            if previousWasEnd, ch.isWhitespace { count += 1 }
            previousWasEnd = false
        }
        return count
    }
}

/// Timing of the most recent generation, for Settings diagnostics and the benchmark.
struct LLMStats: Sendable, Equatable, Codable {
    var promptTokens = 0
    var reusedPromptTokens = 0
    var generatedTokens = 0
    var loadSeconds: Double = 0
    var firstTokenSeconds: Double = 0
    var promptTokensPerSecond: Double = 0
    var tokensPerSecond: Double = 0
}

enum LLMRuntimeError: LocalizedError, Equatable {
    case runtimeUnavailable
    case modelMissing
    case loadFailed(String)
    case contextFailed
    case promptTooLong(Int)
    case decodeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: return tr("The on-device AI runtime isn't part of this build.", "此版本未包含本地 AI 运行时。")
        case .modelMissing: return tr("The on-device AI model hasn't been downloaded yet.", "尚未下载本地 AI 模型。")
        case .loadFailed(let why): return tr("Couldn't load the on-device model (\(why)).", "无法加载本地模型（\(why)）。")
        case .contextFailed: return tr("Not enough memory to start the on-device model.", "内存不足，无法启动本地模型。")
        case .promptTooLong(let n): return tr("The conversation is too long for the on-device model (\(n) tokens).", "对话过长，超出本地模型的处理范围（\(n) tokens）。")
        case .decodeFailed(let code): return tr("The on-device model stopped unexpectedly (\(code)).", "本地模型意外中断（\(code)）。")
        }
    }
}

/// Thread-safe cancellation flag shared between a stream consumer and the generation loop.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Collects raw token bytes and releases only complete UTF-8 scalars, so a Chinese character
/// split across two tokens never reaches the UI as replacement characters.
struct UTF8StreamDecoder: Sendable {
    private var pending: [UInt8] = []

    mutating func append(_ bytes: [UInt8]) -> String {
        pending += bytes
        var cut = pending.count
        // Walk back over a trailing incomplete multi-byte sequence (at most 3 continuation bytes).
        var i = pending.count - 1
        var continuation = 0
        while i >= 0, continuation < 4 {
            let byte = pending[i]
            if byte & 0xC0 == 0x80 {
                continuation += 1
                i -= 1
                continue
            }
            let needed: Int
            if byte & 0x80 == 0 { needed = 1 } else if byte & 0xE0 == 0xC0 { needed = 2 } else if byte & 0xF0 == 0xE0 { needed = 3 } else if byte & 0xF8 == 0xF0 { needed = 4 } else { needed = 1 }
            if continuation + 1 < needed { cut = i }
            break
        }
        let ready = Array(pending[..<cut])
        pending.removeFirst(cut)
        return String(decoding: ready, as: UTF8.self)
    }

    mutating func flush() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}

/// Holds back text that could be the start of a stop sequence until it is disambiguated.
struct StopSequenceFilter: Sendable {
    let stops: [String]
    private var buffer = ""
    private(set) var stopped = false

    init(stops: [String]) { self.stops = stops.filter { !$0.isEmpty } }

    /// Returns the text that is safe to emit now.
    mutating func feed(_ text: String) -> String {
        guard !stopped else { return "" }
        buffer += text
        if let hit = stops.compactMap({ buffer.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            stopped = true
            let out = String(buffer[..<hit.lowerBound])
            buffer = ""
            return out
        }
        // Keep the longest suffix that is a prefix of some stop sequence.
        var keep = 0
        for stop in stops {
            var n = min(stop.count, buffer.count)
            while n > 0 {
                if buffer.hasSuffix(String(stop.prefix(n))) { keep = max(keep, n); break }
                n -= 1
            }
        }
        let emitIndex = buffer.index(buffer.endIndex, offsetBy: -keep)
        let out = String(buffer[..<emitIndex])
        buffer = String(buffer[emitIndex...])
        return out
    }

    mutating func flush() -> String {
        defer { buffer = "" }
        return stopped ? "" : buffer
    }
}

/// llama.cpp wrapper. Every llama call runs on one serial queue, so the C context is never
/// touched concurrently; generation streams text deltas and honours cancellation per token.
///
/// Cache reuse: the exact text already evaluated (prompt + generated reply) is remembered. When the
/// next prompt extends it verbatim, only the new suffix is decoded — this also works for hybrid
/// recurrent models (Qwen3.5) whose state cannot be partially rolled back. Otherwise the longest
/// common token prefix is kept when the memory supports it, else the context is rebuilt.
final class LlamaRuntime: @unchecked Sendable {
    struct Configuration: Sendable, Equatable {
        var contextLength: Int32 = 4096
        var batchSize: Int32 = 512
        var gpuLayers: Int32
        var threads: Int32

        static func deviceDefault(contextLength: Int32 = 4096) -> Configuration {
            // The simulator's Metal can't run ggml kernels, so it is CPU-only there.
            #if targetEnvironment(simulator)
            var gpu: Int32 = 0
            #else
            var gpu: Int32 = 99
            #endif
            if let override = ProcessInfo.processInfo.environment["DEARHOME_GPU_LAYERS"].flatMap(Int32.init) { gpu = override }
            let cores = ProcessInfo.processInfo.activeProcessorCount
            return Configuration(contextLength: contextLength, gpuLayers: gpu, threads: Int32(max(2, min(4, cores - 2))))
        }
    }

    static var isAvailable: Bool {
        #if canImport(llama)
        return true
        #else
        return false
        #endif
    }

    private let queue = DispatchQueue(label: "home.llama.runtime", qos: .userInitiated)
    private let configuration: Configuration
    private let stateLock = NSLock()
    private var _loadedPath: String?
    private var _lastStats = LLMStats()

    #if canImport(llama)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var evaluated: [llama_token] = []
    /// Text whose tokens are exactly `evaluated` (empty when unknown).
    private var evaluatedText = ""
    private static let backendOnce: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()
    #endif

    init(configuration: Configuration = .deviceDefault()) {
        self.configuration = configuration
    }

    deinit {
        #if canImport(llama)
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        #endif
    }

    var loadedPath: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return _loadedPath
    }

    var lastStats: LLMStats {
        stateLock.lock(); defer { stateLock.unlock() }
        return _lastStats
    }

    private func setLoadedPath(_ path: String?) {
        stateLock.lock(); _loadedPath = path; stateLock.unlock()
    }

    private func setStats(_ stats: LLMStats) {
        stateLock.lock(); _lastStats = stats; stateLock.unlock()
    }

    /// Loads (or keeps) the model at `url`. Cheap when the same file is already resident.
    func load(_ url: URL) async throws -> Double {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            queue.async {
                do { continuation.resume(returning: try self.loadSync(url)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func unload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.unloadSync()
                continuation.resume()
            }
        }
    }

    /// Number of tokens `text` occupies (special tokens parsed), or nil when no model is loaded.
    func tokenCount(_ text: String) async -> Int? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            queue.async {
                #if canImport(llama)
                continuation.resume(returning: self.vocab == nil ? nil : self.tokenize(text).count)
                #else
                continuation.resume(returning: nil)
                #endif
            }
        }
    }

    /// Streams the completion of a fully formatted prompt.
    func generate(prompt: String, options: LLMGenerationOptions) -> AsyncThrowingStream<String, Error> {
        let flag = CancellationFlag()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in flag.cancel() }
            queue.async {
                do {
                    try self.generateSync(prompt: prompt, options: options, cancel: flag) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: Queue-confined implementation

    private func loadSync(_ url: URL) throws -> Double {
        #if canImport(llama)
        if loadedPath == url.path, context != nil { return 0 }
        unloadSync()
        guard FileManager.default.fileExists(atPath: url.path) else { throw LLMRuntimeError.modelMissing }
        _ = Self.backendOnce
        let start = Date()
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = configuration.gpuLayers
        guard let loaded = llama_model_load_from_file(url.path, mparams) else {
            throw LLMRuntimeError.loadFailed(url.lastPathComponent)
        }
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(configuration.contextLength)
        cparams.n_batch = UInt32(configuration.batchSize)
        cparams.n_ubatch = UInt32(configuration.batchSize)
        cparams.n_seq_max = 1
        cparams.n_threads = configuration.threads
        cparams.n_threads_batch = configuration.threads
        cparams.no_perf = true
        if configuration.gpuLayers == 0 {
            // Keep every op on the CPU; otherwise ggml still ships work to the Metal device.
            cparams.op_offload = false
            cparams.offload_kqv = false
        }
        guard let ctx = llama_init_from_model(loaded, cparams) else {
            llama_model_free(loaded)
            throw LLMRuntimeError.contextFailed
        }
        model = loaded
        context = ctx
        vocab = llama_model_get_vocab(loaded)
        evaluated = []
        setLoadedPath(url.path)
        let seconds = Date().timeIntervalSince(start)
        var stats = lastStats
        stats.loadSeconds = seconds
        setStats(stats)
        return seconds
        #else
        throw LLMRuntimeError.runtimeUnavailable
        #endif
    }

    private func unloadSync() {
        #if canImport(llama)
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        vocab = nil
        evaluated = []
        evaluatedText = ""
        #endif
        setLoadedPath(nil)
    }

    #if canImport(llama)
    private func tokenize(_ text: String, addSpecial: Bool = true) -> [llama_token] {
        guard let vocab else { return [] }
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 8)
        var n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), addSpecial, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), addSpecial, true)
        }
        return Array(tokens.prefix(Int(max(0, n))))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        guard let vocab else { return [] }
        var buffer = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(0, n))).map { UInt8(bitPattern: $0) }
    }

    /// Decodes `tokens` starting at position `start`, requesting logits for the last one.
    private func decode(_ tokens: ArraySlice<llama_token>, start: Int, batch: inout llama_batch) throws {
        guard let context else { throw LLMRuntimeError.contextFailed }
        var index = tokens.startIndex
        var pos = start
        let chunk = Int(configuration.batchSize)
        while index < tokens.endIndex {
            let end = min(index + chunk, tokens.endIndex)
            batch.n_tokens = 0
            for i in index..<end {
                let slot = Int(batch.n_tokens)
                batch.token[slot] = tokens[i]
                batch.pos[slot] = llama_pos(pos)
                batch.n_seq_id[slot] = 1
                batch.seq_id[slot]![0] = 0
                batch.logits[slot] = (i == tokens.endIndex - 1) ? 1 : 0
                batch.n_tokens += 1
                pos += 1
            }
            let status = llama_decode(context, batch)
            if status != 0 { throw LLMRuntimeError.decodeFailed(status) }
            index = end
        }
    }
    #endif

    private func generateSync(prompt: String, options: LLMGenerationOptions, cancel: CancellationFlag,
                              emit: (String) -> Void) throws {
        #if canImport(llama)
        guard let context, let vocab else { throw LLMRuntimeError.modelMissing }
        let started = Date()
        let memory = llama_get_memory(context)
        let limit = Int(configuration.contextLength) - options.maxTokens - 8

        var promptTokens: [llama_token]
        var common: Int
        let suffix = prompt.utf8.count > evaluatedText.utf8.count && !evaluated.isEmpty && prompt.utf8.starts(with: evaluatedText.utf8)
            ? String(decoding: prompt.utf8.dropFirst(evaluatedText.utf8.count), as: UTF8.self) : nil
        if let suffix, !suffix.isEmpty {
            // Verbatim continuation: decode only what is new.
            promptTokens = evaluated + tokenize(suffix, addSpecial: false)
            common = evaluated.count
        } else {
            promptTokens = tokenize(prompt)
            common = 0
            while common < min(evaluated.count, promptTokens.count), evaluated[common] == promptTokens[common] { common += 1 }
            if common == promptTokens.count { common -= 1 }  // re-decode at least one token for fresh logits
            if common > 0, !llama_memory_seq_rm(memory, 0, llama_pos(common), -1) { common = 0 }
            if common <= 0 {
                llama_memory_clear(memory, true)
                common = 0
            }
        }
        guard promptTokens.count <= limit else {
            llama_memory_clear(memory, true)
            evaluated = []
            evaluatedText = ""
            throw LLMRuntimeError.promptTooLong(promptTokens.count)
        }
        evaluated = Array(promptTokens.prefix(common))
        evaluatedText = ""

        var batch = llama_batch_init(configuration.batchSize, 0, 1)
        defer { llama_batch_free(batch) }
        try decode(promptTokens[common...], start: common, batch: &batch)
        evaluated = promptTokens
        evaluatedText = prompt
        let promptDone = Date()

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), options.penaltyLastN,
                                                                    options.repeatPenalty, 0, options.presencePenalty))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(options.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(options.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_min_p(options.minP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(options.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(options.seed))

        var utf8 = UTF8StreamDecoder()
        var stops = StopSequenceFilter(stops: options.stopSequences)
        var generated = 0
        var firstTokenAt: Date?
        var stats = LLMStats(promptTokens: promptTokens.count, reusedPromptTokens: common, loadSeconds: lastStats.loadSeconds)
        defer {
            let end = Date()
            let genSeconds = firstTokenAt.map { end.timeIntervalSince($0) } ?? 0
            stats.generatedTokens = generated
            stats.firstTokenSeconds = (firstTokenAt ?? end).timeIntervalSince(started)
            let promptSeconds = promptDone.timeIntervalSince(started)
            stats.promptTokensPerSecond = promptSeconds > 0 ? Double(promptTokens.count - common) / promptSeconds : 0
            stats.tokensPerSecond = genSeconds > 0 && generated > 1 ? Double(generated - 1) / genSeconds : 0
            setStats(stats)
        }

        var rawBytes: [UInt8] = []
        var emittedText = ""
        var cleanStop = false
        while generated < options.maxTokens {
            if cancel.isCancelled { break }
            let token = llama_sampler_sample(chain, context, -1)
            if llama_vocab_is_eog(vocab, token) { cleanStop = true; break }
            generated += 1
            if firstTokenAt == nil { firstTokenAt = Date() }
            let bytes = piece(token)
            let text = stops.feed(utf8.append(bytes))
            if !text.isEmpty {
                emit(text)
                emittedText += text
            }
            if stops.stopped { break }
            if let limit = options.maxSentences, SentenceCounter.complete(in: emittedText) >= limit {
                // The sampled token is already part of the reply; decode it, then close the turn.
                rawBytes += bytes
                batch.n_tokens = 1
                batch.token[0] = token
                batch.pos[0] = llama_pos(evaluated.count)
                batch.n_seq_id[0] = 1
                batch.seq_id[0]![0] = 0
                batch.logits[0] = 1
                if llama_decode(context, batch) == 0 {
                    evaluated.append(token)
                    cleanStop = true
                } else {
                    rawBytes.removeLast(bytes.count)
                }
                break
            }
            batch.n_tokens = 1
            batch.token[0] = token
            batch.pos[0] = llama_pos(evaluated.count)
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            let status = llama_decode(context, batch)
            if status != 0 { throw LLMRuntimeError.decodeFailed(status) }
            evaluated.append(token)
            rawBytes += bytes
        }
        let tail = stops.feed(utf8.flush()) + stops.flush()
        if !tail.isEmpty { emit(tail) }
        // The reply is now part of the cache; a following prompt that quotes it verbatim
        // (followed by the end-of-turn marker) continues from here.
        evaluatedText = prompt + String(decoding: rawBytes, as: UTF8.self)
        if cleanStop {
            let end = tokenize("<|im_end|>\n", addSpecial: false)
            if (try? decode(end[...], start: evaluated.count, batch: &batch)) != nil {
                evaluated += end
                evaluatedText += "<|im_end|>\n"
            }
        }
        #else
        throw LLMRuntimeError.runtimeUnavailable
        #endif
    }
}
