import Foundation
import Vapor
import Fluent

// MARK: - Analysis Result

struct AnalysisResult: Codable, Content {
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
        case .noApiKey: return "Kein API-Key konfiguriert."
        case .networkError: return "Netzwerkfehler bei der Claude API"
        case .apiError(let code, let body): return "Claude API Fehler (\(code)): \(String(body.prefix(200)))"
        case .parsingError(let detail): return "Antwort konnte nicht verarbeitet werden: \(detail)"
        }
    }
}

// MARK: - Service

final class ClaudeService: Sendable {
    let client: Client
    let logger: Logger
    let apiKey: String

    init(client: Client, logger: Logger, apiKey: String) {
        self.client = client
        self.logger = logger
        self.apiKey = apiKey
    }

    // MARK: - Public: Analyze single Geschaeft

    func analyzeGeschaeft(_ geschaeft: Geschaeft, on db: Database) async throws {
        guard !apiKey.isEmpty else { throw ClaudeError.noApiKey }

        // Load relationships for prompt building
        try await geschaeft.$wortmeldungen.load(on: db)
        try await geschaeft.$abstimmungen.load(on: db)
        for abstimmung in geschaeft.abstimmungen {
            try await abstimmung.$stimmabgaben.load(on: db)
        }

        let prompt = buildGeschaeftPrompt(geschaeft)
        let result = try await callClaude(prompt: prompt)

        geschaeft.linksRechts = result.linksRechts
        geschaeft.konservativLiberal = result.konservativLiberal
        geschaeft.liberaleWirtschaft = result.liberaleWirtschaft
        geschaeft.innovativerStandort = result.innovativerStandort
        geschaeft.unabhaengigeStromversorgung = result.unabhaengigeStromversorgung
        geschaeft.staerkeResilienz = result.staerkeResilienz
        geschaeft.schlankerStaat = result.schlankerStaat
        try await geschaeft.save(on: db)
    }

    // MARK: - Public: Analyze single Parlamentarier

    func analyzeParlamentarier(_ parlamentarier: Parlamentarier, on db: Database) async throws {
        guard !apiKey.isEmpty else { throw ClaudeError.noApiKey }

        // Load relationships
        try await parlamentarier.$occupations.load(on: db)
        try await parlamentarier.$interests.load(on: db)
        try await parlamentarier.$stimmabgaben.load(on: db)
        for stimmabgabe in parlamentarier.stimmabgaben {
            try await stimmabgabe.$abstimmung.load(on: db)
        }
        try await parlamentarier.$wortmeldungen.load(on: db)
        for wortmeldung in parlamentarier.wortmeldungen {
            try await wortmeldung.$geschaeft.load(on: db)
        }

        let prompt = buildParlamentarierPrompt(parlamentarier)
        let result = try await callClaude(prompt: prompt)

        parlamentarier.linksRechts = result.linksRechts
        parlamentarier.konservativLiberal = result.konservativLiberal
        parlamentarier.liberaleWirtschaft = result.liberaleWirtschaft
        parlamentarier.innovativerStandort = result.innovativerStandort
        parlamentarier.unabhaengigeStromversorgung = result.unabhaengigeStromversorgung
        parlamentarier.staerkeResilienz = result.staerkeResilienz
        parlamentarier.schlankerStaat = result.schlankerStaat
        try await parlamentarier.save(on: db)
    }

    // MARK: - Public: Generate Daily Report

    func generateDailyReport(
        session: Session,
        reportDate: Date,
        geschaefte: [Geschaeft],
        on db: Database
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.noApiKey }

        // Ensure relationships are loaded
        for geschaeft in geschaefte {
            try await geschaeft.$wortmeldungen.load(on: db)
            try await geschaeft.$abstimmungen.load(on: db)
            for abstimmung in geschaeft.abstimmungen {
                try await abstimmung.$stimmabgaben.load(on: db)
                for stimmabgabe in abstimmung.stimmabgaben {
                    try await stimmabgabe.$parlamentarier.load(on: db)
                }
            }
        }

        let prompt = buildDailyReportPrompt(session: session, reportDate: reportDate, geschaefte: geschaefte)
        let reportContent = try await callClaudeForText(prompt: prompt)

        guard !reportContent.isEmpty else {
            throw ClaudeError.parsingError(detail: "Leere Antwort von Claude")
        }
        return reportContent
    }

    // MARK: - Public: Extract Propositions from a Wortmeldung

    func extractPropositionsFromWortmeldung(
        wortmeldung: Wortmeldung,
        on db: Database
    ) async throws -> [PropositionResult] {
        guard !apiKey.isEmpty else { throw ClaudeError.noApiKey }

        try await wortmeldung.$geschaeft.load(on: db)
        try await wortmeldung.$parlamentarier.load(on: db)

        let prompt = buildPropositionPrompt(wortmeldung)
        let propositionDTOs = try await callClaudeForPropositions(prompt: prompt)

        let propositionDate = parseMeetingDate(wortmeldung.meetingDate)
        let geschaeftNr = wortmeldung.geschaeft?.businessShortNumber ?? ""

        var results: [PropositionResult] = []
        for dto in propositionDTOs {
            let proposition = Proposition(
                keyMessage: dto.kernaussage,
                subject: dto.subjekt,
                dateOfProposition: propositionDate,
                source: wortmeldung.speakerFullName,
                geschaeftTitle: wortmeldung.geschaeft?.title ?? geschaeftNr
            )
            proposition.$parlamentarier.id = wortmeldung.$parlamentarier.id
            proposition.$wortmeldung.id = wortmeldung.id
            try await proposition.save(on: db)
            results.append(PropositionResult(keyMessage: dto.kernaussage, subject: dto.subjekt))
        }

        wortmeldung.isPropositionExtracted = true
        try await wortmeldung.save(on: db)

        return results
    }

    struct PropositionResult: Content {
        let keyMessage: String
        let subject: String
    }

    // MARK: - Private: Claude API Call

    private func callClaude(prompt: String) async throws -> AnalysisResult {
        let responseText = try await callClaudeRaw(
            prompt: prompt,
            maxTokens: 2048,
            tools: [ClaudeTool(type: "web_search_20250305", name: "web_search", max_uses: 5)]
        )
        return try parseAnalysisResult(from: responseText)
    }

    private func callClaudeForText(prompt: String) async throws -> String {
        try await callClaudeRaw(prompt: prompt, maxTokens: 8192, tools: [])
    }

    private func callClaudeForPropositions(prompt: String) async throws -> [InternalPropositionDTO] {
        let text = try await callClaudeRaw(prompt: prompt, maxTokens: 4096, tools: [])
        return try parsePropositions(from: text)
    }

    private func callClaudeRaw(prompt: String, maxTokens: Int, tools: [ClaudeTool]) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: maxTokens,
            tools: tools,
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
        return claudeResponse.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    // MARK: - Private: Parse JSON

    private func parseAnalysisResult(from text: String) throws -> AnalysisResult {
        let jsonString = extractJSON(from: text, type: .object)
        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeError.parsingError(detail: "Kein gültiger Text")
        }
        do {
            return try JSONDecoder().decode(AnalysisResult.self, from: data)
        } catch {
            throw ClaudeError.parsingError(detail: String(jsonString.prefix(200)))
        }
    }

    private func parsePropositions(from text: String) throws -> [InternalPropositionDTO] {
        let jsonString = extractJSON(from: text, type: .array)
        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeError.parsingError(detail: "Kein gültiger Text")
        }
        do {
            return try JSONDecoder().decode([InternalPropositionDTO].self, from: data)
        } catch {
            throw ClaudeError.parsingError(detail: String(jsonString.prefix(300)))
        }
    }

    private enum JSONType { case object, array }

    private func extractJSON(from text: String, type: JSONType) -> String {
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

        switch type {
        case .object:
            if let open = jsonString.firstIndex(of: "{"),
               let close = jsonString.lastIndex(of: "}") {
                jsonString = String(jsonString[open...close])
            }
        case .array:
            if let open = jsonString.firstIndex(of: "["),
               let close = jsonString.lastIndex(of: "]") {
                jsonString = String(jsonString[open...close])
            }
        }
        return jsonString
    }

    private struct InternalPropositionDTO: Decodable {
        let kernaussage: String
        let subjekt: String

        enum CodingKeys: String, CodingKey {
            case kernaussage = "Kernaussage"
            case subjekt = "Subjekt"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
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

    private func parseMeetingDate(_ dateString: String?) -> Date? {
        guard let dateString, dateString.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "de_CH")
        return formatter.date(from: dateString)
    }

    // MARK: - Prompt Building

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

        if !geschaeft.abstimmungen.isEmpty {
            parts.append("\n## Abstimmungen")
            for abstimmung in geschaeft.abstimmungen {
                let subject = abstimmung.subject ?? "Abstimmung"
                let jaCount = abstimmung.stimmabgaben.filter { $0.decision == 1 }.count
                let neinCount = abstimmung.stimmabgaben.filter { $0.decision == 2 }.count
                let enthCount = abstimmung.stimmabgaben.filter { $0.decision == 3 }.count
                parts.append("- \(subject): Ja=\(jaCount), Nein=\(neinCount), Enthaltung=\(enthCount)")
            }
        }

        parts.append(analysisInstructions)
        return parts.joined(separator: "\n")
    }

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

        if !p.occupations.isEmpty {
            parts.append("\n## Berufliche Tätigkeit")
            for occ in p.occupations {
                let employer = occ.employer.map { ", \($0)" } ?? ""
                parts.append("- \(occ.occupationName)\(employer)")
            }
        }

        if !p.interests.isEmpty {
            parts.append("\n## Interessenbindungen")
            for interest in p.interests.prefix(15) {
                let paid = interest.paid == true ? " (bezahlt)" : ""
                let function = interest.functionInAgencyText.map { ", \($0)" } ?? ""
                parts.append("- \(interest.interestName)\(function)\(paid)")
            }
        }

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

        let reden = p.wortmeldungen.filter { $0.isRede }.prefix(5)
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

    private func buildPropositionPrompt(_ wortmeldung: Wortmeldung) -> String {
        let text = wortmeldung.plainText
        let speaker = wortmeldung.speakerFullName
        let geschaeftNr = wortmeldung.geschaeft?.businessShortNumber ?? ""
        let geschaeftTitle = wortmeldung.geschaeft?.title ?? ""

        return """
        Auftrag: Extraktion von autarken Kernaussagen

        Kontext: Wortmeldung von \(speaker) zum Geschäft \(geschaeftNr) «\(geschaeftTitle)»

        Analysiere die beigefügte Wortmeldung und erstelle eine umfassende und möglichst vollständige Liste der Kernaussagen. Beachte dabei strikt die folgenden strukturellen und logischen Kriterien für jede einzelne Aussage:
         - Propositionale Struktur: Jede Aussage muss aus einem klaren Subjekt und einem Prädikat (Handlung/Zustand) bestehen.
         - Autarkie: Jede Aussage muss für sich allein stehend ohne den Kontext des restlichen Textes vollumfänglich verständlich sein.
         - Falsifizierbarkeit: Formuliere die Aussagen als Thesen, die theoretisch überprüfbar oder widerlegbar sind.
         - Kausalität oder Mechanismus: Wo möglich, stelle nicht nur einen Fakt fest, sondern den dahinterliegenden Wirkmechanismus oder die Konsequenz.
         - Präzision vor Quantität: Extrahiere nur Aussagen, die einen substanziellen Erkenntnisgewinn bieten.
         - Zitierfähigkeit: Die Kernaussage muss in zukünftigen Diskussionen zitiert werden können.

        Wähle zu jeder Kernaussage das am besten geeignete Subjekt aus folgender Liste:
        Geopolitik - Russland, Geopolitik - China, Geopolitik - USA, Europa und EU,
        Sicherheitspolitik Schweiz, Schweizer Geschichte, Schweizer Wirtschaft, Staatsfinanzen Schweiz,
        Schweizer Politik, Energieversorgung Schweiz, Innovation und Disruption, Künstliche Intelligenz,
        Cyber, Militär und Rüstung, Technologie und Digitalisierung, Zeitenwende,
        Demographie und Gesellschaft, Klimawandel, Leadership,
        Präsentationstechnik und Storytelling, Personal Growth

        Format: JSON-Array mit Attributen "Kernaussage" (Text) und "Subjekt" (aus Liste).
        Gib nur die Liste zurück, ohne einleitende oder abschliessende Worte.

        ## Wortmeldung:

        \(text)
        """
    }

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
        - **Debatte:** Journalistische Zusammenfassung der Wortmeldungen
        - **Abstimmung:** Resultat mit numerischem Ergebnis und Fraktionsstimmverhalten

        Regeln: Deutsch (CH), journalistisch, numerische Resultate, Fraktionsverhalten zeigen.
        """)

        let nationalratGeschaefte = geschaefte.filter { g in
            g.wortmeldungen.contains { $0.councilName == "Nationalrat" && $0.meetingDate == dateKey } ||
            g.abstimmungen.contains { a in
                if let voteEnd = a.voteEnd { return Calendar.current.isDate(voteEnd, inSameDayAs: reportDate) }
                return false
            }
        }

        let staenderatGeschaefte = geschaefte.filter { g in
            g.wortmeldungen.contains { $0.councilName == "Ständerat" && $0.meetingDate == dateKey } ||
            g.abstimmungen.contains { a in
                if let voteEnd = a.voteEnd { return Calendar.current.isDate(voteEnd, inSameDayAs: reportDate) }
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
            parts.append("\nHINWEIS: Es liegen keine Wortmeldungen oder Abstimmungen für dieses Datum vor.")
        }

        return parts.joined(separator: "\n")
    }

    private func buildGeschaeftSection(_ geschaeft: Geschaeft, council: String, dateKey: String, reportDate: Date) -> String {
        var section = "### Geschäft: \(geschaeft.businessShortNumber) – \(geschaeft.title)\n"
        section += "- Typ: \(geschaeft.businessTypeName)\n"
        section += "- Status: \(geschaeft.businessStatusText)\n"

        if let desc = geschaeft.descriptionText, !desc.isEmpty {
            section += "- Beschreibung: \(String(desc.prefix(300)))\n"
        }

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

        let dayVotes = geschaeft.abstimmungen.filter { a in
            if let voteEnd = a.voteEnd { return Calendar.current.isDate(voteEnd, inSameDayAs: reportDate) }
            return false
        }

        if !dayVotes.isEmpty {
            section += "\n#### Abstimmungen:\n"
            for abstimmung in dayVotes {
                let subject = abstimmung.subject ?? "Abstimmung"
                let jaCount = abstimmung.stimmabgaben.filter { $0.decision == 1 }.count
                let neinCount = abstimmung.stimmabgaben.filter { $0.decision == 2 }.count
                let enthCount = abstimmung.stimmabgaben.filter { $0.decision == 3 }.count
                section += "- **\(subject)**\n"
                section += "  - Resultat: Ja=\(jaCount), Nein=\(neinCount), Enthaltung=\(enthCount)\n"

                let factionVotes = Dictionary(grouping: abstimmung.stimmabgaben) {
                    $0.parlamentarier?.parlGroupAbbreviation ?? "?"
                }
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

    private var analysisInstructions: String {
        """

        ## Bewertungsskalen
        1. linksRechts: -1.0 (links) bis +1.0 (rechts)
        2. konservativLiberal: -1.0 (konservativ) bis +1.0 (liberal)
        3. liberaleWirtschaft: 0.0 bis 1.0
        4. innovativerStandort: 0.0 bis 1.0
        5. unabhaengigeStromversorgung: 0.0 bis 1.0
        6. staerkeResilienz: 0.0 bis 1.0
        7. schlankerStaat: 0.0 bis 1.0

        Antworte NUR mit einem JSON-Objekt:
        {"linksRechts": 0.0, "konservativLiberal": 0.0, "liberaleWirtschaft": 0.0, "innovativerStandort": 0.0, "unabhaengigeStromversorgung": 0.0, "staerkeResilienz": 0.0, "schlankerStaat": 0.0}
        """
    }
}

// MARK: - Application Storage

private struct ClaudeServiceKey: StorageKey {
    typealias Value = ClaudeService
}

extension Application {
    var claudeService: ClaudeService {
        get { self.storage[ClaudeServiceKey.self]! }
        set { self.storage[ClaudeServiceKey.self] = newValue }
    }
}

extension Request {
    var claudeService: ClaudeService {
        self.application.claudeService
    }
}
