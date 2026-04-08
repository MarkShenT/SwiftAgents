// DefaultInferenceProviderFactory.swift
// Swarm Framework
//
// Opinionated default inference provider selection.
//
// LegacyAgent (the default tool-calling runtime) uses this factory to attempt
// Apple Foundation Models when no explicit inference provider is configured.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum DefaultInferenceProviderFactory {
    static func makeFoundationModelsProviderIfAvailable() -> (any InferenceProvider)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available else {
                return nil
            }
            return ConduitProviderSelection.foundationModels()
        }
        #endif

        return nil
    }
}
