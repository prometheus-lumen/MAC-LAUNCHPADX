import Foundation

struct SearchResult: Identifiable, Hashable {
    let id: UUID
    let application: InstalledApplication
    let recordID: UUID
    let score: Int
    let launchCount: Int
    let lastLaunchedAt: Date?
}

protocol SearchIndexing: Sendable {
    func search(query: String, records: [(ApplicationRecord, InstalledApplication)], sort: SearchSortOrder) -> [SearchResult]
}

struct SearchIndex: SearchIndexing {
    func search(query: String, records: [(ApplicationRecord, InstalledApplication)], sort: SearchSortOrder) -> [SearchResult] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let results = records.compactMap { record, app -> SearchResult? in
            let name = normalize(app.displayName)
            let alias = normalize(record.alias ?? "")
            let bundleID = normalize(app.bundleIdentifier ?? "")
            let latin = pinyin(app.displayName)
            let compactLatin = normalize(latin)
            let initials = normalize(latin.split(separator: " ").compactMap(\.first).map(String.init).joined())
            guard let textScore = textMatchScore(
                query: normalizedQuery,
                name: name,
                alias: alias,
                bundleID: bundleID,
                pinyin: compactLatin,
                initials: initials
            ) else { return nil }
            let score = textScore + usageBonus(for: record)
            return SearchResult(
                id: record.id,
                application: app,
                recordID: record.id,
                score: score,
                launchCount: record.launchCount,
                lastLaunchedAt: record.lastLaunchedAt
            )
        }
        return results.sorted { lhs, rhs in
            switch sort {
            case .relevance:
                if lhs.score != rhs.score { return lhs.score > rhs.score }
            case .recent:
                if lhs.lastLaunchedAt != rhs.lastLaunchedAt { return (lhs.lastLaunchedAt ?? .distantPast) > (rhs.lastLaunchedAt ?? .distantPast) }
            case .name:
                let comparison = lhs.application.displayName.localizedStandardCompare(rhs.application.displayName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return lhs.application.displayName.localizedStandardCompare(rhs.application.displayName) == .orderedAscending
        }.prefix(9).map { $0 }
    }

    private func textMatchScore(
        query: String,
        name: String,
        alias: String,
        bundleID: String,
        pinyin: String,
        initials: String
    ) -> Int? {
        if name == query { return 1_000 }
        if !alias.isEmpty, alias == query { return 950 }
        if name.hasPrefix(query) { return 850 }
        if !alias.isEmpty, alias.hasPrefix(query) { return 800 }
        if name.contains(query) { return 700 }
        if !alias.isEmpty, alias.contains(query) { return 650 }
        if query.contains("."), bundleID.contains(query) { return 600 }

        guard query.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        if pinyin == query { return 580 }
        if pinyin.hasPrefix(query) { return 520 }
        if query.count >= 2, initials == query { return 500 }
        if query.count >= 2, initials.hasPrefix(query) { return 460 }
        if query.count >= 3, pinyin.contains(query) { return 400 }
        if query.count >= 3, initials.contains(query) { return 360 }
        return nil
    }

    private func usageBonus(for record: ApplicationRecord) -> Int {
        var bonus = min(15, record.launchCount)
        guard let lastLaunchedAt = record.lastLaunchedAt else { return bonus }
        let age = Date.now.timeIntervalSince(lastLaunchedAt)
        if age <= 7 * 86_400 { bonus += 8 }
        else if age <= 30 * 86_400 { bonus += 4 }
        return bonus
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private func pinyin(_ value: String) -> String {
        value.applyingTransform(.toLatin, reverse: false)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ?? value.lowercased()
    }
}
