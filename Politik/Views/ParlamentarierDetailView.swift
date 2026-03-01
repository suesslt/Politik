import SwiftUI
import SwiftData

struct ParlamentarierDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let parlamentarier: Parlamentarier

    @State private var isLoadingDetail = false
    @State private var claudeService = ClaudeService()
    @State private var isAnalyzing = false
    @State private var isExtractingPropositions = false
    @State private var extractionTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private let service = ParlamentService()

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "de_CH")
        return f
    }

    var body: some View {
        List {
            personalSection
            if parlamentarier.hasAnalysis {
                analyseSection
            }
            if parlamentarier.isDetailLoaded {
                enrichedSection
            }
            if !parlamentarier.occupations.isEmpty {
                occupationsSection
            }
            if !parlamentarier.interests.isEmpty {
                interestsSection
            }
            votingRecordSection
            geschaefteSection
            propositionenSection
            wortmeldungenSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(parlamentarier.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Geschaeft.self) { geschaeft in
            GeschaeftDetailView(geschaeft: geschaeft)
        }
        .navigationDestination(for: Abstimmung.self) { abstimmung in
            AbstimmungDetailView(abstimmung: abstimmung)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if isExtractingPropositions {
                        propositionProgressView
                    }
                    Menu {
                        Button {
                            Task { await analyzeParlamentarier() }
                        } label: {
                            Label("KI-Analyse", systemImage: "brain")
                        }
                        .disabled(isAnalyzing)

                        Divider()

                        Button {
                            startPropositionExtraction()
                        } label: {
                            let pending = parlamentarier.wortmeldungen.filter { !$0.isPropositionExtracted && !$0.plainText.isEmpty }.count
                            Label("Kernaussagen extrahieren (\(pending))", systemImage: "text.quote")
                        }
                        .disabled(isExtractingPropositions || parlamentarier.wortmeldungen.isEmpty)

                        if isExtractingPropositions {
                            Button(role: .destructive) {
                                extractionTask?.cancel()
                            } label: {
                                Label("Extraktion abbrechen", systemImage: "stop.circle")
                            }
                        }
                    } label: {
                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Aktionen", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if !parlamentarier.isDetailLoaded {
                await loadDetail()
            }
        }
    }

    // MARK: - KI-Analyse

    private var analyseSection: some View {
        AnalysisResultSection(
            linksRechts: parlamentarier.linksRechts,
            konservativLiberal: parlamentarier.konservativLiberal,
            liberaleWirtschaft: parlamentarier.liberaleWirtschaft,
            innovativerStandort: parlamentarier.innovativerStandort,
            unabhaengigeStromversorgung: parlamentarier.unabhaengigeStromversorgung,
            staerkeResilienz: parlamentarier.staerkeResilienz,
            schlankerStaat: parlamentarier.schlankerStaat
        )
    }

    private func analyzeParlamentarier() async {
        isAnalyzing = true
        do {
            try await claudeService.analyzeParlamentarier(parlamentarier)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    // MARK: - Proposition Extraction

    private func startPropositionExtraction() {
        isExtractingPropositions = true
        claudeService.reset()
        extractionTask = Task {
            await claudeService.extractPropositions(
                parlamentarier: parlamentarier,
                modelContext: modelContext
            )
            isExtractingPropositions = false
        }
    }

    @ViewBuilder
    private var propositionProgressView: some View {
        switch claudeService.phase {
        case .analyzing(let current, let total, let title):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("\(current)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .help("Extrahiere Kernaussagen: \(title)")
        default:
            EmptyView()
        }
    }

    // MARK: - Propositions Section

    private var propositionenSection: some View {
        Section {
            if parlamentarier.propositions.isEmpty {
                Text("Keine Kernaussagen extrahiert")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let grouped = Dictionary(grouping: parlamentarier.propositions) { $0.subject }
                let sortedSubjects = grouped.keys.sorted()

                ForEach(sortedSubjects, id: \.self) { subject in
                    let propositions = grouped[subject]!.sorted { $0.createdAt > $1.createdAt }
                    DisclosureGroup {
                        ForEach(propositions) { proposition in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(proposition.keyMessage)
                                    .font(.subheadline)
                                HStack(spacing: 6) {
                                    if !proposition.geschaeft.isEmpty {
                                        Text(proposition.geschaeft)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let date = proposition.dateOfProposition {
                                        Text(dateFormatter.string(from: date))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } label: {
                        HStack {
                            Text(subject)
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(propositions.count)")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        } header: {
            Label("Kernaussagen (\(parlamentarier.propositions.count))", systemImage: "text.quote")
        }
    }

    // MARK: - Personal Info (basic)

    private var personalSection: some View {
        Section {
            DetailRow(label: "Name", value: parlamentarier.fullName)
            if let party = parlamentarier.partyAbbreviation {
                DetailRow(label: "Partei", value: parlamentarier.partyName ?? party)
            }
            if let group = parlamentarier.parlGroupAbbreviation {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fraktion")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(parlamentarier.parlGroupName ?? group)
                            .font(.subheadline)
                    }
                    Spacer()
                    Text(group)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(parlGroupColor(group).opacity(0.15))
                        .foregroundStyle(parlGroupColor(group))
                        .clipShape(Capsule())
                }
            }
            if let canton = parlamentarier.cantonAbbreviation {
                DetailRow(label: "Kanton", value: parlamentarier.cantonName ?? canton)
            }
            if let council = parlamentarier.councilName {
                DetailRow(label: "Rat", value: council)
            }
            HStack {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(parlamentarier.isActive ? "Aktiv" : "Inaktiv")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(parlamentarier.isActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    .foregroundStyle(parlamentarier.isActive ? .green : .gray)
                    .clipShape(Capsule())
            }
        } header: {
            HStack {
                Label("Person", systemImage: "person")
                if isLoadingDetail {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Enriched Details

    private var enrichedSection: some View {
        Section {
            if let dob = parlamentarier.dateOfBirth {
                DetailRow(label: "Geburtsdatum", value: dateFormatter.string(from: dob))
            }
            if let city = parlamentarier.birthPlaceCity {
                let place = [city, parlamentarier.birthPlaceCanton].compactMap { $0 }.joined(separator: ", ")
                DetailRow(label: "Geburtsort", value: place)
            }
            if let status = parlamentarier.maritalStatusText {
                DetailRow(label: "Zivilstand", value: status)
            }
            if let children = parlamentarier.numberOfChildren, children > 0 {
                DetailRow(label: "Kinder", value: "\(children)")
            }
            if let citizenship = parlamentarier.citizenship {
                DetailRow(label: "Bürgerort", value: citizenship)
            }
            if let nationality = parlamentarier.nationality {
                DetailRow(label: "Nationalität", value: nationality)
            }
            if let election = parlamentarier.dateElection {
                DetailRow(label: "Gewählt am", value: dateFormatter.string(from: election))
            }
            if let joining = parlamentarier.dateJoining {
                DetailRow(label: "Beitritt", value: dateFormatter.string(from: joining))
            }
            if let military = parlamentarier.militaryRankText, !military.isEmpty {
                DetailRow(label: "Militärischer Rang", value: military)
            }
        } header: {
            Label("Details", systemImage: "info.circle")
        }
    }

    // MARK: - Occupations

    private var occupationsSection: some View {
        Section {
            ForEach(parlamentarier.occupations, id: \.occupationName) { occ in
                VStack(alignment: .leading, spacing: 2) {
                    Text(occ.occupationName)
                        .font(.subheadline)
                    if let employer = occ.employer, !employer.isEmpty {
                        Text(employer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let title = occ.jobTitle, !title.isEmpty {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label("Beruf (\(parlamentarier.occupations.count))", systemImage: "briefcase")
        }
    }

    // MARK: - Interests

    private var interestsSection: some View {
        Section {
            ForEach(parlamentarier.interests, id: \.interestName) { interest in
                VStack(alignment: .leading, spacing: 4) {
                    Text(interest.interestName)
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        if let type = interest.interestTypeText {
                            Text(type)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        if let function = interest.functionInAgencyText {
                            Text(function)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if interest.paid == true {
                            Text("Bezahlt")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        } header: {
            Label("Interessenbindungen (\(parlamentarier.interests.count))", systemImage: "link")
        }
    }

    // MARK: - Voting Record

    private var votingRecordSection: some View {
        Section {
            let stimmabgaben = parlamentarier.stimmabgaben
            if stimmabgaben.isEmpty {
                Text("Keine Abstimmungen geladen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let jaCount = stimmabgaben.filter { $0.decision == 1 }.count
                let neinCount = stimmabgaben.filter { $0.decision == 2 }.count
                let enthCount = stimmabgaben.filter { $0.decision == 3 }.count

                HStack(spacing: 16) {
                    VoteBadge(label: "Ja", value: jaCount, color: .green)
                    VoteBadge(label: "Nein", value: neinCount, color: .red)
                    VoteBadge(label: "Enth.", value: enthCount, color: .orange)
                }
                .padding(.vertical, 4)

                let sorted = stimmabgaben
                    .sorted { ($0.abstimmung?.voteEnd ?? .distantPast) > ($1.abstimmung?.voteEnd ?? .distantPast) }

                ForEach(sorted.prefix(20)) { stimmabgabe in
                    if let abstimmung = stimmabgabe.abstimmung {
                        NavigationLink(value: abstimmung) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(abstimmung.businessShortNumber ?? "")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text(abstimmung.subject ?? "Abstimmung")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(stimmabgabe.decisionDisplayText)
                                    .font(.caption.bold())
                                    .foregroundStyle(stimmabgabe.decisionColor)
                            }
                        }
                    }
                }
            }
        } header: {
            Label("Stimmverhalten (\(parlamentarier.stimmabgaben.count))", systemImage: "checkmark.circle")
        }
    }

    // MARK: - Geschaefte

    private var geschaefteSection: some View {
        Section {
            if parlamentarier.geschaefte.isEmpty {
                Text("Keine Geschäfte als Urheber/-in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(parlamentarier.geschaefte.sorted(by: { $0.businessShortNumber > $1.businessShortNumber })) { geschaeft in
                    NavigationLink(value: geschaeft) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(geschaeft.businessShortNumber)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(geschaeft.businessTypeAbbreviation)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            Text(geschaeft.title)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                    }
                }
            }
        } header: {
            Label("Geschäfte als Urheber/-in (\(parlamentarier.geschaefte.count))", systemImage: "doc.text")
        }
    }

    // MARK: - Wortmeldungen

    private var wortmeldungenSection: some View {
        Section {
            let redenOnly = parlamentarier.wortmeldungen
                .filter { $0.isRede }
                .sorted { $0.sortOrder < $1.sortOrder }
            if redenOnly.isEmpty {
                Text("Keine Wortmeldungen geladen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(redenOnly.prefix(20)) { wortmeldung in
                    VStack(alignment: .leading, spacing: 4) {
                        if let geschaeft = wortmeldung.geschaeft {
                            Text(geschaeft.businessShortNumber)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(wortmeldung.plainText)
                            .font(.caption)
                            .lineLimit(3)
                        if let date = wortmeldung.meetingDate {
                            Text(formatDate(date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            let count = parlamentarier.wortmeldungen.filter(\.isRede).count
            Label("Wortmeldungen (\(count))", systemImage: "text.quote")
        }
    }

    // MARK: - Loading

    private func loadDetail() async {
        isLoadingDetail = true
        do {
            if let dto = try await service.fetchParlamentarierDetail(personNumber: parlamentarier.personNumber) {
                parlamentarier.dateOfBirth = ODataDateParser.parse(dto.DateOfBirth)
                parlamentarier.maritalStatusText = dto.MaritalStatusText
                parlamentarier.numberOfChildren = dto.NumberOfChildren
                parlamentarier.birthPlaceCity = dto.BirthPlace_City
                parlamentarier.birthPlaceCanton = dto.BirthPlace_Canton
                parlamentarier.citizenship = dto.Citizenship
                parlamentarier.nationality = dto.Nationality
                parlamentarier.dateJoining = ODataDateParser.parse(dto.DateJoining)
                parlamentarier.dateLeaving = ODataDateParser.parse(dto.DateLeaving)
                parlamentarier.dateElection = ODataDateParser.parse(dto.DateElection)
                parlamentarier.militaryRankText = dto.MilitaryRankText
                parlamentarier.partyName = dto.PartyName
                parlamentarier.parlGroupName = dto.ParlGroupName
                parlamentarier.cantonName = dto.CantonName
                parlamentarier.isDetailLoaded = true
            }

            if parlamentarier.interests.isEmpty {
                let interestDTOs = try await service.fetchPersonInterests(personNumber: parlamentarier.personNumber)
                for dto in interestDTOs {
                    let interest = PersonInterest(
                        personNumber: dto.PersonNumber ?? parlamentarier.personNumber,
                        interestName: dto.InterestName ?? "",
                        interestTypeText: dto.InterestTypeText,
                        functionInAgencyText: dto.FunctionInAgencyText,
                        paid: dto.Paid,
                        organizationTypeText: dto.OrganizationTypeText,
                        parlamentarier: parlamentarier
                    )
                    modelContext.insert(interest)
                }
            }

            if parlamentarier.occupations.isEmpty {
                let occDTOs = try await service.fetchPersonOccupations(personNumber: parlamentarier.personNumber)
                for dto in occDTOs {
                    let occ = PersonOccupation(
                        personNumber: dto.PersonNumber ?? parlamentarier.personNumber,
                        occupationName: dto.OccupationName ?? "",
                        employer: dto.Employer,
                        jobTitle: dto.JobTitle,
                        parlamentarier: parlamentarier
                    )
                    modelContext.insert(occ)
                }
            }

            try modelContext.save()
        } catch {
            // Detail loading is supplementary, fail silently
        }
        isLoadingDetail = false
    }

    private func formatDate(_ dateString: String) -> String {
        guard dateString.count == 8 else { return dateString }
        let day = dateString.suffix(2)
        let month = dateString.dropFirst(4).prefix(2)
        let year = dateString.prefix(4)
        return "\(day).\(month).\(year)"
    }
}

// MARK: - Vote Badge

struct VoteBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
