import Foundation
@testable import Swarm
import Testing

@Suite("WebSearchSupport")
struct WebSearchSupportTests {
    @Test("HTML parser prefers semantic content over boilerplate")
    func htmlParserExtractsStructuredSections() throws {
        let html = """
        <html>
          <head>
            <title>Install Swarm</title>
            <meta name="description" content="Install guide">
            <link rel="canonical" href="https://example.com/docs/install">
          </head>
          <body>
            <nav>Home Docs Pricing</nav>
            <main>
              <h1>Install</h1>
              <p>Run swift build to compile the package.</p>
              <h2>Usage</h2>
              <p>Use websearch in grounded mode for research tasks.</p>
            </main>
            <script>console.log('ignore me')</script>
          </body>
        </html>
        """

        let parsed = HTMLDocumentParser.parse(html, url: try #require(URL(string: "https://example.com/docs/install")))

        #expect(parsed.title == "Install Swarm")
        #expect(parsed.canonicalURL == "https://example.com/docs/install")
        #expect(parsed.description == "Install guide")
        #expect(parsed.sections.count == 2)
        #expect(parsed.sections[0].heading == "Install")
        #expect(parsed.sections[0].text.contains("Run swift build"))
        #expect(parsed.sections[0].text.contains("Home Docs Pricing") == false)
    }

    @Test("Web content extractor writes raw artifacts into the provided store root")
    func extractorUsesProvidedRawRoot() throws {
        let rawRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-extractor-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rawRoot.deletingLastPathComponent()) }

        let html = """
        <html>
          <head><title>API Reference</title></head>
          <body>
            <main>
              <h1>fetch()</h1>
              <p>Parameters are query and detail.</p>
              <pre><code>websearch(mode: "fetch", url: "...")</code></pre>
            </main>
          </body>
        </html>
        """

        let url = try #require(URL(string: "https://docs.example.com/reference/fetch"))
        let payload = WebFetchPayload(
            requestedURL: url,
            finalURL: url,
            statusCode: 200,
            contentType: "text/html; charset=utf-8",
            data: Data(html.utf8),
            etag: "etag-1",
            lastModified: nil,
            notModified: false
        )

        let stored = try WebContentExtractor().extract(
            payload: payload,
            goal: "fetch parameters",
            existingArtifactID: nil,
            rawRootURL: rawRoot
        )

        #expect(stored.artifact.pageType == .apiReference)
        #expect(stored.artifact.rawArtifactRef.hasPrefix(rawRoot.path))
        #expect(FileManager.default.fileExists(atPath: stored.artifact.rawArtifactRef))
        #expect(stored.document.sections.isEmpty == false)
        #expect(stored.document.summary.contains("Parameters"))
    }

    @Test("Merged hits prefer close cached results")
    func mergeHitsPrefersUsefulCachedHits() {
        let cached = WebSearchHit(
            id: "cached-1",
            title: "Cached Docs",
            url: "https://example.com/docs",
            snippet: "Cached result",
            score: 0.82,
            source: "wax",
            cached: true,
            artifactID: "artifact-1"
        )
        let remote = WebSearchHit(
            id: "remote-1",
            title: "Remote Docs",
            url: "https://example.com/docs?ref=search",
            snippet: "Remote result",
            score: 0.90,
            source: "tavily",
            cached: false
        )

        let merged = mergeHits(localHits: [cached], remoteHits: [remote], maxResults: 2)

        #expect(merged.first?.cached == true)
        #expect(merged.first?.artifactID == "artifact-1")
    }

    @Test("Saving a fetched artifact replaces old indexed sections")
    func savingArtifactReplacesIndexedSections() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let configuration = WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: true,
            storeURL: root,
            enabled: true
        )
        let store = try await WaxWebArtifactStore(configuration: configuration)
        let extractor = WebContentExtractor()
        let url = try #require(URL(string: "https://example.com/docs/install"))

        func payload(_ text: String, etag: String) -> WebFetchPayload {
            let html = """
            <html>
              <head><title>Install</title></head>
              <body>
                <main>
                  <h1>Install</h1>
                  <p>\(text)</p>
                </main>
              </body>
            </html>
            """
            return WebFetchPayload(
                requestedURL: url,
                finalURL: url,
                statusCode: 200,
                contentType: "text/html; charset=utf-8",
                data: Data(html.utf8),
                etag: etag,
                lastModified: nil,
                notModified: false
            )
        }

        let first = try extractor.extract(
            payload: payload("Initial instructions", etag: "etag-1"),
            goal: "install instructions",
            existingArtifactID: nil,
            rawRootURL: root.appendingPathComponent("raw", isDirectory: true)
        )
        let savedFirst = try await store.save(first)
        _ = try await store.save(
            extractor.extract(
                payload: payload("Updated instructions", etag: "etag-2"),
                goal: "updated instructions",
                existingArtifactID: savedFirst.artifact.artifactID,
                rawRootURL: root.appendingPathComponent("raw", isDirectory: true)
            )
        )

        let matches = try await store.searchSections(query: "updated instructions", topK: 10)
        #expect(matches.count == 1)
        #expect(matches.first?.section.text.contains("Updated instructions") == true)
    }
}
