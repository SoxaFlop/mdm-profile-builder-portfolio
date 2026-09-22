import Foundation

struct JamfKnowledgeSnippet: Equatable {
    let title: String
    let sourceURL: URL
    let excerpt: String
}

private struct StoredJamfKnowledgeDocument: Codable {
    let title: String
    let sourceURL: URL
    let text: String
    let downloadedAt: Date
}

enum JamfKnowledgeDownloadState: Equatable {
    case notDownloaded
    case downloading(JamfKnowledgeDownloadProgress)
    case ready(documentCount: Int, updatedAt: Date)
    case failed(String)
}

struct JamfKnowledgeDownloadProgress: Equatable {
    enum Phase: Equatable {
        case findingDocuments
        case downloadingDocuments
    }

    let phase: Phase
    let completedDocuments: Int
    let totalDocuments: Int?
    let currentDocumentBytes: Int64
    let currentDocumentTotalBytes: Int64?
    let estimatedSecondsRemaining: TimeInterval?

    static let findingDocuments = JamfKnowledgeDownloadProgress(
        phase: .findingDocuments,
        completedDocuments: 0,
        totalDocuments: nil,
        currentDocumentBytes: 0,
        currentDocumentTotalBytes: nil,
        estimatedSecondsRemaining: nil
    )
}

/// Optional, local-only search index of public Jamf School documentation.
/// It downloads only after an explicit technician action and never uploads a
/// prompt, tenant record, or Jamf credential.
@MainActor
final class JamfSchoolKnowledgeBase: ObservableObject {
    @Published private(set) var state: JamfKnowledgeDownloadState = .notDownloaded

    private var documents: [StoredJamfKnowledgeDocument] = []
    private let maximumDocuments = 250
    private let libraryURL = URL(string: "https://learn.jamf.com/r/en-US/jamf-school-documentation/")!
    private var documentationDownloadStartedAt: Date?

    init() {
        loadSavedIndex()
    }

    func downloadOfficialDocumentation() async {
        documentationDownloadStartedAt = Date()
        state = .downloading(.findingDocuments)
        do {
            let indexHTML = try await downloadText(from: libraryURL) { [weak self] received, expected in
                self?.publishProgress(
                    phase: .findingDocuments,
                    completedDocuments: 0,
                    totalDocuments: nil,
                    currentDocumentBytes: received,
                    currentDocumentTotalBytes: expected
                )
            }
            let discovered = extractDocumentationURLs(from: indexHTML)
            let urls = Array((discovered + starterURLs).reduce(into: Set<URL>()) { $0.insert($1) })
                .sorted { $0.absoluteString < $1.absoluteString }
                .prefix(maximumDocuments)

            var indexed: [StoredJamfKnowledgeDocument] = []
            for (offset, url) in urls.enumerated() {
                publishProgress(
                    phase: .downloadingDocuments,
                    completedDocuments: offset,
                    totalDocuments: urls.count,
                    currentDocumentBytes: 0,
                    currentDocumentTotalBytes: nil
                )
                guard let document = try? await makeDocument(
                    from: url,
                    progress: { [weak self] received, expected in
                        self?.publishProgress(
                            phase: .downloadingDocuments,
                            completedDocuments: offset,
                            totalDocuments: urls.count,
                            currentDocumentBytes: received,
                            currentDocumentTotalBytes: expected
                        )
                    }
                ) else { continue }
                indexed.append(document)
            }
            guard !indexed.isEmpty else {
                throw JamfKnowledgeError.noDocumentsDownloaded
            }
            documents = indexed
            try saveIndex()
            state = .ready(documentCount: indexed.count, updatedAt: Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func snippets(for prompt: String, maximum: Int = 3) -> [JamfKnowledgeSnippet] {
        let queryWords = searchableWords(in: prompt)
        guard !queryWords.isEmpty else { return [] }

        var matches: [(document: StoredJamfKnowledgeDocument, score: Int)] = []
        for document in documents {
            let haystack = (document.title + " " + document.text).lowercased()
            let score = queryWords.reduce(into: 0) { result, word in
                if haystack.contains(word) { result += 1 }
            }
            if score > 0 { matches.append((document, score)) }
        }
        return matches
            .sorted {
                $0.score == $1.score
                    ? $0.document.title < $1.document.title
                    : $0.score > $1.score
            }
            .prefix(maximum)
            .map { match in
                JamfKnowledgeSnippet(
                    title: match.document.title,
                    sourceURL: match.document.sourceURL,
                    excerpt: String(match.document.text.prefix(1_200))
                )
            }
    }

    private var starterURLs: [URL] {
        [
            "Creating_a_Profile",
            "Configuring_a_Restrictions_Profile",
            "Configuring_a_Safelist_and_Blocklist_Profile_for_Mobile_Devices",
            "Configuring_a_Layout_for_Devices",
            "Configuring_a_Web_Content_Filter_Profile_for_Mobile_Devices",
            "Configuring_a_Wi-Fi_Profile_for_Mobile_Devices",
            "Adding_Devices_to_a_Static_Device_Group"
        ].compactMap { URL(string: "https://learn.jamf.com/r/en-US/jamf-school-documentation/\($0)") }
    }

    private func makeDocument(
        from url: URL,
        progress: @escaping (Int64, Int64?) -> Void
    ) async throws -> StoredJamfKnowledgeDocument {
        let html = try await downloadText(from: url, progress: progress)
        let title = html.capture(pattern: #"<title[^>]*>(.*?)</title>"#) ?? url.lastPathComponent.replacingOccurrences(of: "_", with: " ")
        let text = html
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 120 else { throw JamfKnowledgeError.documentTooShort }
        return StoredJamfKnowledgeDocument(
            title: title.replacingOccurrences(of: "&amp;", with: "&"),
            sourceURL: url,
            text: text,
            downloadedAt: Date()
        )
    }

    private func downloadText(
        from url: URL,
        progress: @escaping (Int64, Int64?) -> Void = { _, _ in }
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("MDM-Copilot local documentation indexer", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw JamfKnowledgeError.downloadFailed
        }
        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        var data = Data()
        data.reserveCapacity(expected.map(Int.init) ?? 8_192)
        var received: Int64 = 0
        var lastPublished: Int64 = 0
        for try await byte in bytes {
            data.append(byte)
            received += 1
            if received - lastPublished >= 32_768 {
                progress(received, expected)
                lastPublished = received
            }
        }
        progress(received, expected)
        guard let text = String(data: data, encoding: .utf8) else {
            throw JamfKnowledgeError.downloadFailed
        }
        return text
    }

    private func publishProgress(
        phase: JamfKnowledgeDownloadProgress.Phase,
        completedDocuments: Int,
        totalDocuments: Int?,
        currentDocumentBytes: Int64,
        currentDocumentTotalBytes: Int64?
    ) {
        let remaining: TimeInterval?
        if let totalDocuments,
           completedDocuments > 0,
           let startedAt = documentationDownloadStartedAt {
            let averageSecondsPerDocument = Date().timeIntervalSince(startedAt) / Double(completedDocuments)
            remaining = max(0, averageSecondsPerDocument * Double(totalDocuments - completedDocuments))
        } else {
            remaining = nil
        }
        state = .downloading(JamfKnowledgeDownloadProgress(
            phase: phase,
            completedDocuments: completedDocuments,
            totalDocuments: totalDocuments,
            currentDocumentBytes: currentDocumentBytes,
            currentDocumentTotalBytes: currentDocumentTotalBytes,
            estimatedSecondsRemaining: remaining
        ))
    }

    private func extractDocumentationURLs(from html: String) -> [URL] {
        let expression = try! NSRegularExpression(pattern: #"href=[\"']([^\"']+)[\"']"#, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: (html as NSString).length)
        return expression.matches(in: html, range: range).compactMap { match in
            let value = (html as NSString).substring(with: match.range(at: 1))
            guard let url = URL(string: value, relativeTo: libraryURL)?.absoluteURL,
                  url.host == libraryURL.host,
                  url.path.contains("/jamf-school-documentation/") else { return nil }
            return url
        }
    }

    private func searchableWords(in prompt: String) -> [String] {
        prompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private func loadSavedIndex() {
        let sourceURL = FileManager.default.fileExists(atPath: storageURL.path)
            ? storageURL
            : legacyStorageURL
        guard let data = try? Data(contentsOf: sourceURL),
              let saved = try? JSONDecoder().decode([StoredJamfKnowledgeDocument].self, from: data),
              !saved.isEmpty else { return }
        documents = saved
        state = .ready(documentCount: saved.count, updatedAt: saved.map(\.downloadedAt).max() ?? .distantPast)
        if sourceURL == legacyStorageURL {
            try? saveIndex()
        }
    }

    private func saveIndex() throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(documents)
        try data.write(to: storageURL, options: .atomic)
    }

    private var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MDM Profile Builder Demo", isDirectory: true)
            .appendingPathComponent("JamfSchoolKnowledge.json")
    }

    private var legacyStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MDM Profile Builder Demo", isDirectory: true)
            .appendingPathComponent("JamfSchoolKnowledge.json")
    }
}

private enum JamfKnowledgeError: LocalizedError {
    case downloadFailed
    case documentTooShort
    case noDocumentsDownloaded

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "The Jamf School documentation page could not be downloaded."
        case .documentTooShort: "The downloaded page did not contain enough readable documentation."
        case .noDocumentsDownloaded: "No official Jamf School documentation pages could be indexed."
        }
    }
}

private extension String {
    func capture(pattern: String) -> String? {
        let expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: (self as NSString).length)
        guard let match = expression.firstMatch(in: self, range: range), match.numberOfRanges > 1 else { return nil }
        return (self as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
