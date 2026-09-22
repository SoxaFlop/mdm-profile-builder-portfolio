import Foundation

protocol TrustedTimeProviding {
    func trustedDate() async throws -> Date
}

enum TrustedTimeError: LocalizedError {
    case insufficientSources
    case sourcesDisagree

    var errorDescription: String? {
        switch self {
        case .insufficientSources:
            "Trusted time could not be obtained from enough independent HTTPS sources."
        case .sourcesDisagree:
            "The trusted time sources disagree. Check the network and try again."
        }
    }
}

struct HTTPSTrustedTimeProvider: TrustedTimeProviding {
    var endpoints: [URL] = [
        URL(string: "https://www.apple.com/")!,
        URL(string: "https://www.cloudflare.com/")!,
        URL(string: "https://www.microsoft.com/")!
    ]
    var maximumDifference: TimeInterval = 5 * 60

    func trustedDate() async throws -> Date {
        let endpoints = endpoints
        let dates = await withTaskGroup(of: Date?.self, returning: [Date].self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await Self.fetchDate(from: endpoint)
                }
            }
            var values: [Date] = []
            for await value in group {
                if let value { values.append(value) }
            }
            return values.sorted()
        }

        guard dates.count >= 2 else {
            throw TrustedTimeError.insufficientSources
        }

        let matchingPairs = dates.indices.flatMap { firstIndex in
            dates.indices.compactMap { secondIndex -> (Date, Date)? in
                guard secondIndex > firstIndex else { return nil }
                let first = dates[firstIndex]
                let second = dates[secondIndex]
                return second.timeIntervalSince(first) <= maximumDifference
                    ? (first, second)
                    : nil
            }
        }
        guard let closestPair = matchingPairs.min(by: {
            $0.1.timeIntervalSince($0.0) < $1.1.timeIntervalSince($1.0)
        }) else {
            throw TrustedTimeError.sourcesDisagree
        }
        return Date(timeIntervalSince1970: (
            closestPair.0.timeIntervalSince1970 + closestPair.1.timeIntervalSince1970
        ) / 2)
    }

    private static func fetchDate(from endpoint: URL) async -> Date? {
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "HEAD"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<500).contains(response.statusCode),
                  let value = response.value(forHTTPHeaderField: "Date") else {
                return nil
            }
            return parseHTTPDate(value)
        } catch {
            return nil
        }
    }

    private static func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

struct FixedTrustedTimeProvider: TrustedTimeProviding {
    var date: Date

    func trustedDate() async throws -> Date { date }
}
