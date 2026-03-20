import Foundation

/// Safe verbs for writing durable workspace memory notes.
public actor WorkspaceWriter {
    private let workspace: AgentWorkspace

    init(workspace: AgentWorkspace) {
        self.workspace = workspace
    }

    @discardableResult
    public func recordFact(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .fact, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func recordDecision(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .decision, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func createTask(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .task, title: title, body: content, tags: tags, status: "open")
    }

    @discardableResult
    public func recordLesson(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .lesson, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func recordHandoff(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .handoff, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func completeTask(id: String, resolution: String? = nil) throws -> URL {
        let taskDirectory = workspace.memoryDirectory.appendingPathComponent(WorkspaceMemoryNote.Kind.task.directoryName, isDirectory: true)
        let taskURL = try findNote(id: id, in: taskDirectory)
        let existingTask = try workspace.parseMemoryNote(at: taskURL, expectedKind: .task)
        let updatedRevision = existingTask.revision + 1
        let updatedBody: String
        if let resolution, !resolution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedBody = "\(existingTask.body)\n\nResolution:\n\(resolution.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            updatedBody = existingTask.body
        }

        let markdown = noteMarkdown(
            id: existingTask.id,
            kind: .task,
            title: existingTask.title,
            tags: existingTask.tags,
            status: "completed",
            revision: updatedRevision,
            body: updatedBody
        )
        try markdown.write(to: taskURL, atomically: true, encoding: .utf8)
        return taskURL
    }
}

private extension WorkspaceWriter {
    func createNote(
        kind: WorkspaceMemoryNote.Kind,
        title: String,
        body: String,
        tags: [String],
        status: String?
    ) throws -> URL {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString.lowercased()
        let fileName = "\(slug(from: trimmedTitle.isEmpty ? id : trimmedTitle))-\(id.prefix(8)).md"
        let directory = workspace.memoryDirectory.appendingPathComponent(kind.directoryName, isDirectory: true)
        let url = directory.appendingPathComponent(fileName)

        let markdown = noteMarkdown(
            id: id,
            kind: kind,
            title: trimmedTitle.isEmpty ? id : trimmedTitle,
            tags: tags,
            status: status,
            revision: 1,
            body: trimmedBody
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func noteMarkdown(
        id: String,
        kind: WorkspaceMemoryNote.Kind,
        title: String,
        tags: [String],
        status: String?,
        revision: Int,
        body: String
    ) -> String {
        var lines = [
            "---",
            "schema_version: 1",
            "id: \(id)",
            "kind: \(kind.rawValue)",
            "title: \(escaped(title))",
            "updated_at: \(ISO8601DateFormatter().string(from: Date()))",
            "revision: \(revision)",
        ]

        if !tags.isEmpty {
            lines.append("tags:")
            lines.append(contentsOf: tags.map { "  - \(escaped($0))" })
        }

        if let status {
            lines.append("status: \(escaped(status))")
        }

        lines.append("---")
        lines.append(body)
        return lines.joined(separator: "\n")
    }

    func findNote(id: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw AgentWorkspaceError.invalidMemoryNote(path: directory.path, reason: "task directory not found")
        }

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            if let note = try? workspace.parseMemoryNote(at: url, expectedKind: .task), note.id == id {
                return url
            }
        }

        throw AgentWorkspaceError.invalidMemoryNote(path: directory.path, reason: "task '\(id)' not found")
    }

    func slug(from text: String) -> String {
        let pieces = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let slug = pieces.joined(separator: "-")
        return slug.isEmpty ? "note" : slug
    }

    func escaped(_ value: String) -> String {
        if value.contains(":") || value.contains("#") || value.contains("\"") || value.contains("'") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return value
    }
}
