import Foundation
import SwiftData

// MARK: - Analysis Result

struct AnalysisResult: Codable {
    let linksRechts: Double?
    let konservativLiberal: Double?
    let liberaleWirtschaft: Double?
    let innovativerStandort: Double?
    let unabhaengigeStromversorgung: Double?
    let staerkeResilienz: Double?
    let schlankerStaat: Double?
}

// MARK: - Claude API DTOs

struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let tools: [ClaudeTool]
    let messages: [ClaudeMessage]
}

struct ClaudeTool: Encodable {
    let type: String
    let name: String
    let max_uses: Int
}

struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

struct ClaudeResponse: Decodable {
    let content: [ClaudeContentBlock]
}

struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case noApiKey
    case networkError
    case apiError(statusCode: Int, body: String)
    case parsingError(detail: String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Kein API-Key konfiguriert. Bitte unter «Daten» eingeben."
        case .networkError:
            return "Netzwerkfehler bei der Claude API"
        case .apiError(let code, let body):
            return "Claude API Fehler (\(code)): \(String(body.prefix(200)))"
        case .parsingError(let detail):
            return "Antwort konnte nicht verarbeitet werden: \(detail)"
        }
    }
}

// MARK: - Service

@MainActor @Observable
final class ClaudeService {

    enum AnalysisPhase: Equatable {
        case idle
        case analyzing(current: Int, total: Int, title: String)
        case completed(successCount: Int, errorCount: Int)
        case error(message: String)
    }

    static let apiKeyStorageKey = "claude_api_key"

    var phase: AnalysisPhase = .idle

    // MARK: - Public: Analyze single Geschaeft

    func analyzeGeschaeft(_ geschaeft: Geschaeft) async throws {
        let apiKey = try getApiKey()
        let prompt = buildGeschaeftPrompt(geschaeft)
        let result = try await callClaude(prompt: prompt, apiKey: apiKey)

        geschaeft.linksRechts = result.linksRechts
        geschaeft.konservativLiberal = result.konservativLiberal
        geschaeft.liberaleWirtschaft = result.liberaleWirtschaft
        geschaeft.innovativerStandort = result.innovativerStandort
        geschaeft.unabhaengigeStromversorgung = result.unabhaengigeStromversorgung
        geschaeft.staerkeResilienz = result.staerkeResilienz
        geschaeft.schlankerStaat = result.schlankerStaat
    }

    // MARK: - Public: Analyze single Parlamentarier

    func analyzeParlamentarier(_ parlamentarier: Parlamentarier) async throws {
        let apiKey = try getApiKey()
        let prompt = buildParlamentarierPrompt(parlamentarier)
        let result = try await callClaude(prompt: prompt, apiKey: apiKey)

        parlamentarier.linksRechts = result.linksRechts
        parlamentarier.konservativLiberal = result.konservativLiberal
        parlamentarier.liberaleWirtschaft = result.liberaleWirtschaft
        parlamentarier.innovativerStandort = result.innovativerStandort
        parlamentarier.unabhaengigeStromversorgung = result.unabhaengigeStromversorgung
        parlamentarier.staerkeResilienz = result.staerkeResilienz
        parlamentarier.schlankerStaat = result.schlankerStaat
    }

    // MARK: - Public: Analyze all Geschaefte in a Session

    func analyzeSession(_ session: Session, modelContext: ModelContext) async {
        let geschaefte = session.geschaefte.filter { !$0.hasAnalysis }
        let total = geschaefte.count

        guard total > 0 else {
            phase = .completed(successCount: 0, errorCount: 0)
            return
        }

        var successCount = 0
        var errorCount = 0

        for (index, geschaeft) in geschaefte.enumerated() {
            guard !Task.isCancelled else {
                phase = .completed(successCount: successCount, errorCount: errorCount)
                return
            }

            phase = .analyzing(current: index + 1, total: total, title: geschaeft.businessShortNumber)

            do {
                try await analyzeGeschaeft(geschaeft)
                try modelContext.save()
                successCount += 1
            } catch {
                errorCount += 1
                // Continue to next
            }
        }

        phase = .completed(successCount: successCount, errorCount: errorCount)
    }

    // MARK: - Public: Analyze all Parlamentarier

    func analyzeAllParlamentarier(_ parlamentarierList: [Parlamentarier], forceReanalyze: Bool, modelContext: ModelContext) async {
        let targets = forceReanalyze ? parlamentarierList : parlamentarierList.filter { !$0.hasAnalysis }
        let total = targets.count

        guard total > 0 else {
            phase = .completed(successCount: 0, errorCount: 0)
            return
        }

        var successCount = 0
        var errorCount = 0

        for (index, person) in targets.enumerated() {
            guard !Task.isCancelled else {
                phase = .completed(successCount: successCount, errorCount: errorCount)
                return
            }

            phase = .analyzing(current: index + 1, total: total, title: person.fullName)

            do {
                try await analyzeParlamentarier(person)
                try modelContext.save()
                successCount += 1
            } catch {
                errorCount += 1
                // Continue to next
            }
        }

        phase = .completed(successCount: successCount, errorCount: errorCount)
    }

    // MARK: - Public: Extract Propositions from Wortmeldungen

    func extractPropositions(
        parlamentarier: Parlamentarier,
        modelContext: ModelContext
    ) async {
        let wortmeldungen = parlamentarier.wortmeldungen
            .filter { !$0.isPropositionExtracted && !$0.plainText.isEmpty }
        let total = wortmeldungen.count

        guard total > 0 else {
            phase = .completed(successCount: 0, errorCount: 0)
            return
        }

        var successCount = 0
        var errorCount = 0

        for (index, wortmeldung) in wortmeldungen.enumerated() {
            guard !Task.isCancelled else {
                phase = .completed(successCount: successCount, errorCount: errorCount)
                return
            }

            let geschaeftNr = wortmeldung.geschaeft?.businessShortNumber ?? ""
            phase = .analyzing(current: index + 1, total: total, title: geschaeftNr)

            do {
                let apiKey = try getApiKey()
                let prompt = buildPropositionPrompt(wortmeldung)
                let propositionDTOs = try await callClaudeForPropositions(prompt: prompt, apiKey: apiKey)

                // Parse meetingDate to Date
                let propositionDate = parseMeetingDate(wortmeldung.meetingDate)

                for dto in propositionDTOs {
                    let proposition = Proposition(
                        keyMessage: dto.kernaussage,
                        subject: dto.subjekt,
                        dateOfProposition: propositionDate,
                        source: parlamentarier.fullName,
                        geschaeft: wortmeldung.geschaeft?.title ?? geschaeftNr,
                        parlamentarier: parlamentarier,
                        wortmeldung: wortmeldung
                    )
                    modelContext.insert(proposition)
                }

                wortmeldung.isPropositionExtracted = true
                try modelContext.save()
                successCount += 1
            } catch {
                errorCount += 1
                // Continue to next
            }
        }

        phase = .completed(successCount: successCount, errorCount: errorCount)
    }

    // MARK: - Public: Extract Propositions from a single Wortmeldung

    func extractPropositionsFromWortmeldung(
        wortmeldung: Wortmeldung,
        modelContext: ModelContext
    ) async throws {
        guard !wortmeldung.plainText.isEmpty else { return }

        phase = .analyzing(current: 1, total: 1, title: wortmeldung.geschaeft?.businessShortNumber ?? "")

        let apiKey = try getApiKey()
        let prompt = buildPropositionPrompt(wortmeldung)
        let propositionDTOs = try await callClaudeForPropositions(prompt: prompt, apiKey: apiKey)

        let propositionDate = parseMeetingDate(wortmeldung.meetingDate)
        let geschaeftNr = wortmeldung.geschaeft?.businessShortNumber ?? ""

        for dto in propositionDTOs {
            let proposition = Proposition(
                keyMessage: dto.kernaussage,
                subject: dto.subjekt,
                dateOfProposition: propositionDate,
                source: wortmeldung.speakerFullName,
                geschaeft: wortmeldung.geschaeft?.title ?? geschaeftNr,
                parlamentarier: wortmeldung.parlamentarier,
                wortmeldung: wortmeldung
            )
            modelContext.insert(proposition)
        }

        wortmeldung.isPropositionExtracted = true
        try modelContext.save()
        phase = .completed(successCount: 1, errorCount: 0)
    }

    // MARK: - Public: Generate Daily Report

    func generateDailyReport(
        session: Session,
        reportDate: Date,
        geschaefte: [Geschaeft],
        modelContext: ModelContext
    ) async throws -> String {
        let apiKey = try getApiKey()
        let prompt = buildDailyReportPrompt(session: session, reportDate: reportDate, geschaefte: geschaefte)

        phase = .analyzing(current: 1, total: 1, title: "Tagesbericht")

        let reportContent = try await callClaudeForText(prompt: prompt, apiKey: apiKey)

        phase = .completed(successCount: 1, errorCount: 0)
        return reportContent
    }

    func reset() {
        phase = .idle
    }

    // MARK: - Private: API Key

    private func getApiKey() throws -> String {
        guard let key = UserDefaults.standard.string(forKey: Self.apiKeyStorageKey),
              !key.isEmpty else {
            throw ClaudeError.noApiKey
        }
        return key
    }

    // MARK: - Private: Claude API Call

    private func callClaude(prompt: String, apiKey: String) async throws -> AnalysisResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 2048,
            tools: [ClaudeTool(type: "web_search_20250305", name: "web_search", max_uses: 5)],
            messages: [ClaudeMessage(role: "user", content: prompt)]
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        // Extract all text blocks
        let allText = claudeResponse.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")

        return try parseAnalysisResult(from: allText)
    }

    // MARK: - Private: Parse JSON from Claude response

    private func parseAnalysisResult(from text: String) throws -> AnalysisResult {
        var jsonString = text

        // Strip ```json ... ``` wrapping
        if let startRange = jsonString.range(of: "```json") {
            jsonString = String(jsonString[startRange.upperBound...])
        } else if let startRange = jsonString.range(of: "```") {
            jsonString = String(jsonString[startRange.upperBound...])
        }
        if let endRange = jsonString.range(of: "```") {
            jsonString = String(jsonString[..<endRange.lowerBound])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object boundaries
        if let openBrace = jsonString.firstIndex(of: "{"),
           let closeBrace = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[openBrace...closeBrace])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeError.parsingError(detail: "Kein gültiger Text")
        }

        do {
            return try JSONDecoder().decode(AnalysisResult.self, from: data)
        } catch {
            throw ClaudeError.parsingError(detail: String(jsonString.prefix(200)))
        }
    }

    // MARK: - Private: Build Geschaeft Prompt

    private func buildGeschaeftPrompt(_ geschaeft: Geschaeft) -> String {
        var parts: [String] = []

        parts.append("""
        Du bist ein Experte für Schweizer Politik. Analysiere das folgende parlamentarische Geschäft \
        und bewerte es auf den unten definierten Skalen. Nutze die Web-Suche, um zusätzliche Informationen \
        über das Geschäft \(geschaeft.businessShortNumber) zu finden.
        """)

        parts.append("\n## Geschäft")
        parts.append("- Nummer: \(geschaeft.businessShortNumber)")
        parts.append("- Titel: \(geschaeft.title)")
        parts.append("- Typ: \(geschaeft.businessTypeName) (\(geschaeft.businessTypeAbbreviation))")
        parts.append("- Status: \(geschaeft.businessStatusText)")

        if let desc = geschaeft.descriptionText, !desc.isEmpty {
            parts.append("- Beschreibung: \(String(desc.prefix(500)))")
        }
        if let tags = geschaeft.tagNames, !tags.isEmpty {
            parts.append("- Themen: \(tags)")
        }
        if let dept = geschaeft.responsibleDepartmentName {
            parts.append("- Zuständiges Departement: \(dept)")
        }
        if let submittedBy = geschaeft.submittedBy, !submittedBy.isEmpty {
            parts.append("- Eingereicht von: \(submittedBy)")
        }

        // Wortmeldungen (max 10, je 200 Zeichen)
        let reden = geschaeft.wortmeldungen
            .filter { $0.isRede }
            .sorted { $0.sortOrder < $1.sortOrder }
            .prefix(10)
        if !reden.isEmpty {
            parts.append("\n## Wortmeldungen (Auszüge)")
            for rede in reden {
                let snippet = String(rede.plainText.prefix(200))
                let speaker = rede.speakerFullName
                let group = rede.parlGroupAbbreviation ?? ""
                parts.append("- \(speaker) (\(group)): \(snippet)…")
            }
        }

        // Abstimmungen
        if !geschaeft.abstimmungen.isEmpty {
            parts.append("\n## Abstimmungen")
            for abstimmung in geschaeft.abstimmungen {
                let subject = abstimmung.subject ?? "Abstimmung"
                parts.append("- \(subject): Ja=\(abstimmung.jaCount), Nein=\(abstimmung.neinCount), Enthaltung=\(abstimmung.enthaltungCount)")
            }
        }

        parts.append(analysisInstructions)
        return parts.joined(separator: "\n")
    }

    // MARK: - Private: Build Parlamentarier Prompt

    private func buildParlamentarierPrompt(_ p: Parlamentarier) -> String {
        var parts: [String] = []

        parts.append("""
        Du bist ein Experte für Schweizer Politik. Analysiere das politische Profil \
        des folgenden Parlamentariers und bewerte ihn/sie auf den unten definierten Skalen. \
        Nutze die Web-Suche, um zusätzliche Informationen über \(p.fullName) zu finden.
        """)

        parts.append("\n## Parlamentarier/-in")
        parts.append("- Name: \(p.fullName)")
        if let party = p.partyAbbreviation {
            parts.append("- Partei: \(p.partyName ?? party)")
        }
        if let group = p.parlGroupAbbreviation {
            parts.append("- Fraktion: \(p.parlGroupName ?? group)")
        }
        if let canton = p.cantonAbbreviation {
            parts.append("- Kanton: \(p.cantonName ?? canton)")
        }
        if let council = p.councilName {
            parts.append("- Rat: \(council)")
        }

        // Berufe
        if !p.occupations.isEmpty {
            parts.append("\n## Berufliche Tätigkeit")
            for occ in p.occupations {
                let employer = occ.employer.map { ", \($0)" } ?? ""
                parts.append("- \(occ.occupationName)\(employer)")
            }
        }

        // Interessen (max 15)
        if !p.interests.isEmpty {
            parts.append("\n## Interessenbindungen")
            for interest in p.interests.prefix(15) {
                let paid = interest.paid == true ? " (bezahlt)" : ""
                let function = interest.functionInAgencyText.map { ", \($0)" } ?? ""
                parts.append("- \(interest.interestName)\(function)\(paid)")
            }
        }

        // Stimmverhalten (letzte 30)
        let recentVotes = p.stimmabgaben
            .sorted { ($0.abstimmung?.voteEnd ?? .distantPast) > ($1.abstimmung?.voteEnd ?? .distantPast) }
            .prefix(30)
        if !recentVotes.isEmpty {
            parts.append("\n## Stimmverhalten (letzte Abstimmungen)")
            for stimmabgabe in recentVotes {
                if let abstimmung = stimmabgabe.abstimmung {
                    let subject = abstimmung.subject ?? abstimmung.businessShortNumber ?? "?"
                    parts.append("- \(subject): \(stimmabgabe.decisionDisplayText)")
                }
            }
        }

        // Wortmeldungen (max 5, je 200 Zeichen)
        let reden = p.wortmeldungen
            .filter { $0.isRede }
            .prefix(5)
        if !reden.isEmpty {
            parts.append("\n## Wortmeldungen (Auszüge)")
            for rede in reden {
                let snippet = String(rede.plainText.prefix(200))
                let geschaeftNr = rede.geschaeft?.businessShortNumber ?? ""
                parts.append("- [\(geschaeftNr)] \(snippet)…")
            }
        }

        parts.append(analysisInstructions)
        return parts.joined(separator: "\n")
    }

    // MARK: - Private: Proposition Prompt

    private func buildPropositionPrompt(_ wortmeldung: Wortmeldung) -> String {
        let text = wortmeldung.plainText
        let speaker = wortmeldung.speakerFullName
        let geschaeftNr = wortmeldung.geschaeft?.businessShortNumber ?? ""
        let geschaeftTitle = wortmeldung.geschaeft?.title ?? ""

        return """
        Auftrag: Extraktion von autarken Kernaussagen

        Kontext: Wortmeldung von \(speaker) zum Geschäft \(geschaeftNr) «\(geschaeftTitle)»

        Analysiere die beigefügte Wortmeldung und erstelle eine umfassende und möglichst vollständige Liste der Kernaussagen. Beachte dabei strikt die folgenden strukturellen und logischen Kriterien für jede einzelne Aussage:
         - Propositionale Struktur: Jede Aussage muss aus einem klaren Subjekt und einem Prädikat (Handlung/Zustand) bestehen. Keine bloßen Schlagworte oder Nominalphrasen.
         - Autarkie: Jede Aussage muss für sich allein stehend ohne den Kontext des restlichen Textes vollumfänglich verständlich sein.
         - Falsifizierbarkeit: Formuliere die Aussagen als Thesen, die theoretisch überprüfbar oder widerlegbar sind. Vermeide vage Füllwörter (vielleicht, man könnte, eventuell).
         - Kausalität oder Mechanismus: Wo möglich, stelle nicht nur einen Fakt fest, sondern den dahinterliegenden Wirkmechanismus oder die Konsequenz (Struktur: "[Subjekt] bewirkt [Folge] durch [Mechanismus]").
         - Präzision vor Quantität: Extrahiere nur Aussagen, die einen substanziellen Erkenntnisgewinn bieten, keine trivialen Beschreibungen.
         - Zitierfähigkeit: Die Kernaussage muss in zukünftigen Diskussionen zitiert werden können, ohne dass der Urheber der Wortmeldung diese bestreiten kann.

        Wähle zu jeder Kernaussage das am besten geeignete Subjekt aus folgender Liste:
        - Geopolitik - Russland
        - Geopolitik - China
        - Geopolitik - USA
        - Europa und EU

        - Sicherheitspolitik Schweiz
        - Schweizer Geschichte
        - Schweizer Wirtschaft
        - Staatsfinanzen Schweiz
        - Schweizer Politik
        - Energieversorgung Schweiz

        - Innovation und Disruption
        - Künstliche Intelligenz
        - Cyber
        - Militär und Rüstung
        - Technologie und Digitalisierung

        - Zeitenwende
        - Demographie und Gesellschaft
        - Klimawandel

        - Leadership
        - Präsentationstechnik und Storytelling
        - Personal Growth

        Format der Ausgabe:
            Gib die Kernaussagen in einem JSON-Format mit folgenden Attributen zurück:
             - Kernaussage (Text)
             - Subjekt (Eintrag aus vorhergehender Liste)

        Gib nur die Liste zurück, ohne einleitende oder abschliessende Worte oder Vorgehen.

        ## Wortmeldung:

        \(text)
        """
    }

    // MARK: - Private: Claude API Call for Propositions

    private struct PropositionDTO: Decodable {
        let kernaussage: String
        let subjekt: String

        enum CodingKeys: String, CodingKey {
            case kernaussage = "Kernaussage"
            case subjekt = "Subjekt"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Try capitalized keys first, then lowercase
            if let k = try? container.decode(String.self, forKey: .kernaussage) {
                kernaussage = k
            } else {
                let lc = try decoder.container(keyedBy: LowercaseCodingKeys.self)
                kernaussage = try lc.decode(String.self, forKey: .kernaussage)
            }
            if let s = try? container.decode(String.self, forKey: .subjekt) {
                subjekt = s
            } else {
                let lc = try decoder.container(keyedBy: LowercaseCodingKeys.self)
                subjekt = try lc.decode(String.self, forKey: .subjekt)
            }
        }

        private enum LowercaseCodingKeys: String, CodingKey {
            case kernaussage
            case subjekt
        }
    }

    private func callClaudeForPropositions(prompt: String, apiKey: String) async throws -> [PropositionDTO] {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 4096,
            tools: [],
            messages: [ClaudeMessage(role: "user", content: prompt)]
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        let allText = claudeResponse.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")

        return try parsePropositions(from: allText)
    }

    private func parsePropositions(from text: String) throws -> [PropositionDTO] {
        var jsonString = text

        // Strip ```json ... ``` wrapping
        if let startRange = jsonString.range(of: "```json") {
            jsonString = String(jsonString[startRange.upperBound...])
        } else if let startRange = jsonString.range(of: "```") {
            jsonString = String(jsonString[startRange.upperBound...])
        }
        if let endRange = jsonString.range(of: "```") {
            jsonString = String(jsonString[..<endRange.lowerBound])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON array boundaries
        if let openBracket = jsonString.firstIndex(of: "["),
           let closeBracket = jsonString.lastIndex(of: "]") {
            jsonString = String(jsonString[openBracket...closeBracket])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeError.parsingError(detail: "Kein gültiger Text")
        }

        do {
            return try JSONDecoder().decode([PropositionDTO].self, from: data)
        } catch {
            throw ClaudeError.parsingError(detail: String(jsonString.prefix(300)))
        }
    }

    private func parseMeetingDate(_ dateString: String?) -> Date? {
        guard let dateString, dateString.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "de_CH")
        return formatter.date(from: dateString)
    }

    // MARK: - Private: Claude API Call for Text (Daily Report)

    private func callClaudeForText(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 8192,
            tools: [],
            messages: [ClaudeMessage(role: "user", content: prompt)]
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        let allText = claudeResponse.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")

        guard !allText.isEmpty else {
            throw ClaudeError.parsingError(detail: "Leere Antwort von Claude")
        }

        return allText
    }

    // MARK: - Private: Build Daily Report Prompt

    private func buildDailyReportPrompt(session: Session, reportDate: Date, geschaefte: [Geschaeft]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.locale = Locale(identifier: "de_CH")
        let dateString = dateFormatter.string(from: reportDate)

        let shortFormatter = DateFormatter()
        shortFormatter.dateFormat = "yyyyMMdd"
        let dateKey = shortFormatter.string(from: reportDate)

        var parts: [String] = []

        parts.append("""
        Du bist ein erfahrener Parlamentsjournalist der Schweiz. Erstelle einen Tagesbericht über die \
        Verhandlungen im Schweizer Parlament vom \(dateString) während der Session «\(session.sessionName)».

        Der Bericht soll im Markdown-Format verfasst werden und folgende Struktur haben:

        # Parlamentsbericht \(dateString)
        ## Session: \(session.sessionName)

        Dann für jeden Rat (Nationalrat und Ständerat) getrennt:

        ## Nationalrat / ## Ständerat

        ### [Geschäftstitel] ([Geschäftsnummer])
        - Kurze Zusammenfassung des Geschäfts
        - **Debatte:** Journalistische Zusammenfassung der Wortmeldungen. Pointierte Meinungen und \
        Widersprüche sollen hervorgehoben werden. Schreibe lebendig und anschaulich.
        - **Abstimmung:** Resultat mit Fraktionsstimmverhalten

        Wichtige Regeln:
        - Schreibe auf Deutsch (Schweizer Hochdeutsch)
        - Journalistischer, lebendiger Stil
        - Pointierte Meinungen und Kontroversen hervorheben
        - Bei Abstimmungen zeige das Stimmverhalten der Fraktionen
        - Nur Geschäfte aufnehmen, zu denen Wortmeldungen oder Abstimmungen vom angegebenen Tag vorliegen
        - Wenn keine Daten für einen Rat vorliegen, den Abschnitt weglassen
        """)

        // Group by council
        let nationalratGeschaefte = geschaefte.filter { g in
            g.wortmeldungen.contains { $0.councilName == "Nationalrat" && $0.meetingDate == dateKey } ||
            g.abstimmungen.contains { abstimmung in
                if let voteEnd = abstimmung.voteEnd {
                    return Calendar.current.isDate(voteEnd, inSameDayAs: reportDate)
                }
                return false
            }
        }

        let staenderatGeschaefte = geschaefte.filter { g in
            g.wortmeldungen.contains { $0.councilName == "Ständerat" && $0.meetingDate == dateKey } ||
            g.abstimmungen.contains { abstimmung in
                if let voteEnd = abstimmung.voteEnd {
                    return Calendar.current.isDate(voteEnd, inSameDayAs: reportDate)
                }
                return false
            }
        }

        if !nationalratGeschaefte.isEmpty {
            parts.append("\n---\n## Daten Nationalrat\n")
            for geschaeft in nationalratGeschaefte {
                parts.append(buildGeschaeftSection(geschaeft, council: "Nationalrat", dateKey: dateKey, reportDate: reportDate))
            }
        }

        if !staenderatGeschaefte.isEmpty {
            parts.append("\n---\n## Daten Ständerat\n")
            for geschaeft in staenderatGeschaefte {
                parts.append(buildGeschaeftSection(geschaeft, council: "Ständerat", dateKey: dateKey, reportDate: reportDate))
            }
        }

        if nationalratGeschaefte.isEmpty && staenderatGeschaefte.isEmpty {
            parts.append("\nHINWEIS: Es liegen keine Wortmeldungen oder Abstimmungen für dieses Datum vor. Erstelle einen kurzen Bericht, der dies feststellt.")
        }

        return parts.joined(separator: "\n")
    }

    private func buildGeschaeftSection(_ geschaeft: Geschaeft, council: String, dateKey: String, reportDate: Date) -> String {
        var section = ""
        section += "### Geschäft: \(geschaeft.businessShortNumber) – \(geschaeft.title)\n"
        section += "- Typ: \(geschaeft.businessTypeName)\n"
        section += "- Status: \(geschaeft.businessStatusText)\n"

        if let desc = geschaeft.descriptionText, !desc.isEmpty {
            section += "- Beschreibung: \(String(desc.prefix(300)))\n"
        }

        // Wortmeldungen for this day and council
        let daySpeeches = geschaeft.wortmeldungen
            .filter { $0.councilName == council && $0.meetingDate == dateKey && $0.isRede }
            .sorted { $0.sortOrder < $1.sortOrder }

        if !daySpeeches.isEmpty {
            section += "\n#### Wortmeldungen (\(daySpeeches.count)):\n"
            for speech in daySpeeches {
                let group = speech.parlGroupAbbreviation ?? "?"
                let plainText = String(speech.plainText.prefix(500))
                section += "- **\(speech.speakerFullName)** (\(group)): \(plainText)\n"
            }
        }

        // Abstimmungen for this day
        let dayVotes = geschaeft.abstimmungen.filter { abstimmung in
            if let voteEnd = abstimmung.voteEnd {
                return Calendar.current.isDate(voteEnd, inSameDayAs: reportDate)
            }
            return false
        }

        if !dayVotes.isEmpty {
            section += "\n#### Abstimmungen:\n"
            for abstimmung in dayVotes {
                let subject = abstimmung.subject ?? "Abstimmung"
                let meaningYes = abstimmung.meaningYes ?? "Ja"
                let meaningNo = abstimmung.meaningNo ?? "Nein"
                section += "- **\(subject)**\n"
                section += "  - Bedeutung Ja: \(meaningYes) / Nein: \(meaningNo)\n"
                section += "  - Resultat: Ja=\(abstimmung.jaCount), Nein=\(abstimmung.neinCount), Enthaltung=\(abstimmung.enthaltungCount)\n"

                // Group votes by faction
                let factionVotes = Dictionary(grouping: abstimmung.stimmabgaben) { $0.parlamentarier?.parlGroupAbbreviation ?? "?" }
                var factionSummaries: [String] = []
                for (faction, votes) in factionVotes.sorted(by: { $0.key < $1.key }) {
                    let ja = votes.filter { $0.decision == 1 }.count
                    let nein = votes.filter { $0.decision == 2 }.count
                    let enth = votes.filter { $0.decision == 3 }.count
                    factionSummaries.append("\(faction): Ja=\(ja) Nein=\(nein) Enth=\(enth)")
                }
                section += "  - Fraktionen: \(factionSummaries.joined(separator: " | "))\n"
            }
        }

        return section
    }

    // MARK: - Shared instructions

    private var analysisInstructions: String {
        """

        ## Bewertungsskalen
        Bewerte auf diesen Skalen:
        1. linksRechts: -1.0 (links) bis +1.0 (rechts) — Politische Ausrichtung
        2. konservativLiberal: -1.0 (konservativ) bis +1.0 (liberal) — Gesellschaftliche Haltung
        3. liberaleWirtschaft: 0.0 bis 1.0 — Förderung einer liberalen Wirtschaftsordnung
        4. innovativerStandort: 0.0 bis 1.0 — Förderung von Innovation und Standort Schweiz
        5. unabhaengigeStromversorgung: 0.0 bis 1.0 — Unabhängige und zukunftsgerichtete Stromversorgung der Schweiz
        6. staerkeResilienz: 0.0 bis 1.0 — Stärke und Resilienz, starke Armee
        7. schlankerStaat: 0.0 bis 1.0 — Schlanker Staat, Entbürokratisierung, tiefe Steuern

        Antworte NUR mit einem JSON-Objekt, ohne weitere Erklärungen:
        {"linksRechts": 0.0, "konservativLiberal": 0.0, "liberaleWirtschaft": 0.0, "innovativerStandort": 0.0, "unabhaengigeStromversorgung": 0.0, "staerkeResilienz": 0.0, "schlankerStaat": 0.0}
        """
    }
}
