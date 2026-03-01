import SwiftUI
import SwiftData

struct GeschaeftDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let geschaeft: Geschaeft

    @State private var isLoadingTranscripts = false
    @State private var isLoadingUrheber = false
    @State private var errorMessage: String?
    @State private var claudeService = ClaudeService()
    @State private var isAnalyzing = false

    private let service = ParlamentService()

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "de_CH")
        return formatter
    }

    private var sortedWortmeldungen: [Wortmeldung] {
        geschaeft.wortmeldungen.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var reden: [Wortmeldung] {
        sortedWortmeldungen.filter { $0.isRede }
    }

    var body: some View {
        List {
            headerSection
            if geschaeft.hasAnalysis {
                analyseSection
            }
            statusSection
            detailsSection
            if let description = geschaeft.descriptionText, !description.isEmpty {
                descriptionSection(description)
            }
            if let tags = geschaeft.tagNames, !tags.isEmpty {
                tagsSection(tags)
            }
            if !geschaeft.abstimmungen.isEmpty {
                abstimmungenSection
            }
            wortmeldungenSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(geschaeft.businessShortNumber)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Abstimmung.self) { abstimmung in
            AbstimmungDetailView(abstimmung: abstimmung)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await analyzeGeschaeft() }
                } label: {
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Analysieren", systemImage: "brain")
                    }
                }
                .disabled(isAnalyzing)
            }
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if geschaeft.urheber == nil {
                await loadUrheber()
            }
            if reden.isEmpty {
                await loadTranscripts()
            }
        }
    }

    // MARK: - KI-Analyse

    private var analyseSection: some View {
        AnalysisResultSection(
            linksRechts: geschaeft.linksRechts,
            konservativLiberal: geschaeft.konservativLiberal,
            liberaleWirtschaft: geschaeft.liberaleWirtschaft,
            innovativerStandort: geschaeft.innovativerStandort,
            unabhaengigeStromversorgung: geschaeft.unabhaengigeStromversorgung,
            staerkeResilienz: geschaeft.staerkeResilienz,
            schlankerStaat: geschaeft.schlankerStaat
        )
    }

    private func analyzeGeschaeft() async {
        isAnalyzing = true
        do {
            try await claudeService.analyzeGeschaeft(geschaeft)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(geschaeft.businessTypeAbbreviation)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(typeColor.opacity(0.15))
                        .foregroundStyle(typeColor)
                        .clipShape(Capsule())
                    Text(geschaeft.businessTypeName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(geschaeft.title)
                    .font(.title3.bold())
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            DetailRow(label: "Status", value: geschaeft.businessStatusText)
            if let date = geschaeft.businessStatusDate {
                DetailRow(label: "Status-Datum", value: dateFormatter.string(from: date))
            }
        } header: {
            Label("Status", systemImage: "flag")
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section {
            if let urheber = geschaeft.urheber {
                NavigationLink(value: urheber) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Urheber/-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(urheber.fullName)
                                .font(.subheadline)
                            if let group = urheber.parlGroupAbbreviation {
                                Text(group)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(parlGroupColor(group).opacity(0.1))
                                    .foregroundStyle(parlGroupColor(group))
                                    .clipShape(Capsule())
                            }
                            if let canton = urheber.cantonAbbreviation {
                                Text(canton)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if let submittedBy = geschaeft.submittedBy, !submittedBy.isEmpty {
                DetailRow(label: "Eingereicht von", value: submittedBy)
            }
            if isLoadingUrheber {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Urheber wird geladen…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let date = geschaeft.submissionDate {
                DetailRow(label: "Eingereicht am", value: dateFormatter.string(from: date))
            }
            if let council = geschaeft.submissionCouncilName {
                DetailRow(label: "Rat", value: council)
            }
            if let dept = geschaeft.responsibleDepartmentName,
               let abbr = geschaeft.responsibleDepartmentAbbreviation {
                DetailRow(label: "Departement", value: "\(dept) (\(abbr))")
            }
        } header: {
            Label("Details", systemImage: "info.circle")
        }
        .navigationDestination(for: Parlamentarier.self) { parlamentarier in
            ParlamentarierDetailView(parlamentarier: parlamentarier)
        }
    }

    // MARK: - Description

    private func descriptionSection(_ description: String) -> some View {
        Section {
            Text(description)
                .font(.body)
        } header: {
            Label("Beschreibung", systemImage: "doc.text")
        }
    }

    // MARK: - Tags

    private func tagsSection(_ tags: String) -> some View {
        Section {
            FlowLayout(spacing: 6) {
                ForEach(tags.components(separatedBy: "|"), id: \.self) { tag in
                    let trimmed = tag.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        Text(trimmed)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        } header: {
            Label("Themen", systemImage: "tag")
        }
    }

    // MARK: - Abstimmungen

    private var abstimmungenSection: some View {
        Section {
            let sorted = geschaeft.abstimmungen.sorted { ($0.voteEnd ?? .distantPast) > ($1.voteEnd ?? .distantPast) }
            ForEach(sorted) { abstimmung in
                NavigationLink(value: abstimmung) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(abstimmung.subject ?? "Abstimmung")
                            .font(.subheadline)
                            .lineLimit(2)
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("\(abstimmung.jaCount)")
                                    .font(.caption.monospacedDigit())
                            }
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                Text("\(abstimmung.neinCount)")
                                    .font(.caption.monospacedDigit())
                            }
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 8, height: 8)
                                Text("\(abstimmung.enthaltungCount)")
                                    .font(.caption.monospacedDigit())
                            }
                            Spacer()
                            if abstimmung.jaCount > abstimmung.neinCount {
                                Text("Angenommen")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else if abstimmung.neinCount > abstimmung.jaCount {
                                Text("Abgelehnt")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        if let voteEnd = abstimmung.voteEnd {
                            Text(dateFormatter.string(from: voteEnd))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        } header: {
            Label("Abstimmungen (\(geschaeft.abstimmungen.count))", systemImage: "hand.thumbsup")
        }
    }

    // MARK: - Wortmeldungen

    private var wortmeldungenSection: some View {
        Section {
            if isLoadingTranscripts {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Wortmeldungen werden geladen…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if reden.isEmpty {
                VStack(spacing: 8) {
                    Text("Keine Wortmeldungen verfügbar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await loadTranscripts() }
                    } label: {
                        Label("Erneut laden", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            } else {
                ForEach(reden) { wortmeldung in
                    WortmeldungRowView(wortmeldung: wortmeldung)
                }
            }
        } header: {
            Label("Wortmeldungen (\(reden.count))", systemImage: "text.quote")
        }
    }

    // MARK: - Loading

    private func loadUrheber() async {
        isLoadingUrheber = true
        do {
            if let roleDTO = try await service.fetchUrheber(businessID: geschaeft.id),
               let memberNumber = roleDTO.MemberCouncilNumber {
                let existing = fetchParlamentarier(personNumber: memberNumber)
                if let existing {
                    geschaeft.urheber = existing
                } else if let dto = try await service.fetchParlamentarier(personNumber: memberNumber) {
                    let parlamentarier = Parlamentarier(
                        personNumber: dto.PersonNumber ?? memberNumber,
                        firstName: dto.FirstName ?? "",
                        lastName: dto.LastName ?? "",
                        partyAbbreviation: dto.PartyAbbreviation,
                        parlGroupAbbreviation: dto.ParlGroupAbbreviation,
                        cantonAbbreviation: dto.CantonAbbreviation,
                        councilName: dto.CouncilName,
                        councilAbbreviation: dto.CouncilAbbreviation,
                        isActive: dto.Active ?? false
                    )
                    modelContext.insert(parlamentarier)
                    geschaeft.urheber = parlamentarier
                }
                try modelContext.save()
            }
        } catch {
            // Silently fail for urheber loading
        }
        isLoadingUrheber = false
    }

    private func loadTranscripts() async {
        isLoadingTranscripts = true
        do {
            // Remove old non-speech entries that may block reload
            let oldNonSpeech = geschaeft.wortmeldungen.filter { !$0.isRede }
            for old in oldNonSpeech {
                modelContext.delete(old)
            }

            let dtos = try await service.fetchTranscripts(businessID: geschaeft.id)
            let existingIDs = Set(geschaeft.wortmeldungen.map(\.id))
            for dto in dtos {
                guard let dtoID = dto.ID, !existingIDs.contains(dtoID) else { continue }
                let parlamentarier: Parlamentarier? = if let pn = dto.PersonNumber {
                    fetchParlamentarier(personNumber: pn)
                } else {
                    nil
                }
                let wortmeldung = Wortmeldung(
                    id: dtoID,
                    speakerFullName: dto.SpeakerFullName ?? "",
                    speakerFunction: dto.SpeakerFunction,
                    text: dto.Text ?? "",
                    meetingDate: dto.MeetingDate,
                    parlGroupAbbreviation: dto.ParlGroupAbbreviation,
                    cantonAbbreviation: dto.CantonAbbreviation,
                    councilName: dto.CouncilName,
                    sortOrder: dto.SortOrder ?? 0,
                    type: dto.TranscriptType ?? 0,
                    startTime: ODataDateParser.parse(dto.Start),
                    endTime: ODataDateParser.parse(dto.End),
                    geschaeft: geschaeft,
                    parlamentarier: parlamentarier
                )
                modelContext.insert(wortmeldung)
            }
            try modelContext.save()
        } catch {
            errorMessage = String(describing: error)
        }
        isLoadingTranscripts = false
    }

    private func fetchParlamentarier(personNumber: Int) -> Parlamentarier? {
        let descriptor = FetchDescriptor<Parlamentarier>(
            predicate: #Predicate { $0.personNumber == personNumber }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private var typeColor: Color {
        switch geschaeft.businessTypeAbbreviation {
        case "BRG": return .purple
        case "Mo.": return .blue
        case "Po.": return .teal
        case "Pa.Iv.": return .orange
        case "Kt.Iv.": return .red
        case "Ip.": return .green
        case "Fra.": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Wortmeldung Row

struct WortmeldungRowView: View {
    let wortmeldung: Wortmeldung

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if !wortmeldung.speakerFullName.isEmpty {
                    Text(wortmeldung.speakerFullName)
                        .font(.subheadline.bold())
                }
                Spacer()
                if let group = wortmeldung.parlGroupAbbreviation {
                    Text(group)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(parlGroupColor(group).opacity(0.1))
                        .foregroundStyle(parlGroupColor(group))
                        .clipShape(Capsule())
                }
                if let canton = wortmeldung.cantonAbbreviation {
                    Text(canton)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let function = wortmeldung.speakerFunction, !function.isEmpty {
                Text(function)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(wortmeldung.plainText)
                .font(.caption)
                .lineLimit(4)
                .foregroundStyle(.primary)
            if let date = wortmeldung.meetingDate {
                Text(formatMeetingDate(date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatMeetingDate(_ dateString: String) -> String {
        guard dateString.count == 8 else { return dateString }
        let day = dateString.suffix(2)
        let month = dateString.dropFirst(4).prefix(2)
        let year = dateString.prefix(4)
        return "\(day).\(month).\(year)"
    }
}

// MARK: - Helpers

func parlGroupColor(_ abbreviation: String) -> Color {
    switch abbreviation {
    case "S": return .red
    case "G", "GL": return .green
    case "V": return .blue // Changed from dark green
    case "RL", "FDP": return .blue
    case "M-E", "M": return .orange
    case "BD": return .yellow
    default: return .secondary
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
