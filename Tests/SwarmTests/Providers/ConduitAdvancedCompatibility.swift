#if !canImport(ConduitAdvanced)
import Conduit

enum ConduitAdvanced {
    typealias ModelIdentifying = Conduit.ModelIdentifying
    typealias ProviderType = Conduit.ProviderType
    typealias TextGenerator = Conduit.TextGenerator
    typealias GenerateConfig = Conduit.GenerateConfig
    typealias Message = Conduit.Message
    typealias GenerationResult = Conduit.GenerationResult
    typealias GenerationChunk = Conduit.GenerationChunk
    typealias PartialToolCall = Conduit.PartialToolCall
    typealias GeneratedContent = Conduit.GeneratedContent
    typealias UsageStats = Conduit.UsageStats
    typealias OpenRouterDataCollection = Conduit.OpenRouterDataCollection

    enum Transcript {
        typealias ToolCall = Conduit.Transcript.ToolCall
    }
}
#endif
