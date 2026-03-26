import Foundation

/// Checkpoint persistence configuration for advanced workflows.
public struct WorkflowCheckpointing: Sendable {
    let backend: any WorkflowDurableCheckpointStore

    init(backend: some WorkflowDurableCheckpointStore) {
        self.backend = backend
    }

    /// In-memory checkpoint persistence.
    public static func inMemory() -> WorkflowCheckpointing {
        WorkflowCheckpointing(backend: WorkflowInMemoryCheckpointStore())
    }

    /// File-system checkpoint persistence rooted at `directory`.
    public static func fileSystem(directory: URL) -> WorkflowCheckpointing {
        WorkflowCheckpointing(backend: WorkflowFileCheckpointStore(directory: directory))
    }
}
