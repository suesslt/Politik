import SwiftUI
import SwiftData

// MARK: - Sort Criterion

enum GeschaeftSortCriterion: String, CaseIterable, Identifiable {
    case nummer
    case titel
    case einreichedatum
    case geschaeftstyp
    case linksRechts
    case konservativLiberal
    case liberaleWirtschaft
    case innovativerStandort
    case stromversorgung
    case staerkeResilienz
    case schlankerStaat

    var id: Self { self }

    var label: String {
        switch self {
        case .nummer: "Nummer"
        case .titel: "Titel"
        case .einreichedatum: "Einreichedatum"
        case .geschaeftstyp: "Geschäftstyp"
        case .linksRechts: "Links / Rechts"
        case .konservativLiberal: "Konservativ / Liberal"
        case .liberaleWirtschaft: "Liberale Wirtschaft"
        case .innovativerStandort: "Innovativer Standort"
        case .stromversorgung: "Stromversorgung"
        case .staerkeResilienz: "Stärke / Resilienz"
        case .schlankerStaat: "Schlanker Staat"
        }
    }

    var icon: String {
        switch self {
        case .nummer: "number"
        case .titel: "textformat.abc"
        case .einreichedatum: "calendar"
        case .geschaeftstyp: "tag"
        case .linksRechts: "arrow.left.arrow.right"
        case .konservativLiberal: "arrow.up.arrow.down"
        case .liberaleWirtschaft: "banknote"
        case .innovativerStandort: "lightbulb"
        case .stromversorgung: "bolt"
        case .staerkeResilienz: "shield"
        case .schlankerStaat: "building.columns"
        }
    }
}

// MARK: - Main View

struct GeschaeftListView: View {
    @Environment(\.modelContext) private var modelContext
    let session: Session

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showSessionAnalysis = false
    @State private var showFilterSheet = false

    // Sort state
    @State private var sortCriterion: GeschaeftSortCriterion = .nummer
    @State private var sortAscending: Bool = false

    // Filter state
    @State private var filterGeschaeftstypen: Set<String> = []
    @State private var filterRat: String?
    @State private var filterDepartemente: Set<String> = []
    @State private var filterStatus: Set<String> = []
    @State private var filterNurAnalysierte: Bool = false

    private let service = ParlamentService()

    // MARK: - Derived Data

    private var availableGeschaeftstypen: [String] {
        Set(session.geschaefte.map(\.businessTypeAbbreviation)).sorted()
    }

    private var availableRaete: [String] {
        Set(session.geschaefte.compactMap(\.submissionCouncilName)).sorted()
    }

    private var availableDepartemente: [String] {
        Set(session.geschaefte.compactMap(\.responsibleDepartmentAbbreviation)).sorted()
    }

    private var availableStatus: [String] {
        Set(session.geschaefte.map(\.businessStatusText)).sorted()
    }

    private var activeFilterCount: Int {
        var count = 0
        if !filterGeschaeftstypen.isEmpty { count += 1 }
        if filterRat != nil { count += 1 }
        if !filterDepartemente.isEmpty { count += 1 }
        if !filterStatus.isEmpty { count += 1 }
        if filterNurAnalysierte { count += 1 }
        return count
    }

    private var filteredAndSorted: [Geschaeft] {
        var result = Array(session.geschaefte)

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query)
                || $0.businessShortNumber.lowercased().contains(query)
                || $0.businessTypeName.lowercased().contains(query)
                || ($0.submittedBy?.lowercased().contains(query) ?? false)
                || ($0.tagNames?.lowercased().contains(query) ?? false)
                || ($0.responsibleDepartmentName?.lowercased().contains(query) ?? false)
            }
        }

        // Filters
        if !filterGeschaeftstypen.isEmpty {
            result = result.filter { filterGeschaeftstypen.contains($0.businessTypeAbbreviation) }
        }
        if let rat = filterRat {
            result = result.filter { $0.submissionCouncilName == rat }
        }
        if !filterDepartemente.isEmpty {
            result = result.filter { filterDepartemente.contains($0.responsibleDepartmentAbbreviation ?? "") }
        }
        if !filterStatus.isEmpty {
            result = result.filter { filterStatus.contains($0.businessStatusText) }
        }
        if filterNurAnalysierte {
            result = result.filter(\.hasAnalysis)
        }

        // Sort
        result.sort { a, b in
            let comparison: Bool
            switch sortCriterion {
            case .nummer:
                comparison = a.businessShortNumber.localizedCompare(b.businessShortNumber) == .orderedAscending
            case .titel:
                comparison = a.title.localizedCompare(b.title) == .orderedAscending
            case .einreichedatum:
                comparison = (a.submissionDate ?? .distantPast) < (b.submissionDate ?? .distantPast)
            case .geschaeftstyp:
                comparison = a.businessTypeAbbreviation.localizedCompare(b.businessTypeAbbreviation) == .orderedAscending
            case .linksRechts:
                comparison = (a.linksRechts ?? -999) < (b.linksRechts ?? -999)
            case .konservativLiberal:
                comparison = (a.konservativLiberal ?? -999) < (b.konservativLiberal ?? -999)
            case .liberaleWirtschaft:
                comparison = (a.liberaleWirtschaft ?? -1) < (b.liberaleWirtschaft ?? -1)
            case .innovativerStandort:
                comparison = (a.innovativerStandort ?? -1) < (b.innovativerStandort ?? -1)
            case .stromversorgung:
                comparison = (a.unabhaengigeStromversorgung ?? -1) < (b.unabhaengigeStromversorgung ?? -1)
            case .staerkeResilienz:
                comparison = (a.staerkeResilienz ?? -1) < (b.staerkeResilienz ?? -1)
            case .schlankerStaat:
                comparison = (a.schlankerStaat ?? -1) < (b.schlankerStaat ?? -1)
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        Group {
            if session.geschaefte.isEmpty && isLoading {
                ProgressView("Geschäfte werden geladen…")
            } else if session.geschaefte.isEmpty {
                ContentUnavailableView(
                    "Keine Geschäfte",
                    systemImage: "doc.text",
                    description: Text("Ziehe nach unten, um Geschäfte zu laden.")
                )
            } else {
                geschaeftList
            }
        }
        .navigationTitle(session.sessionName)
        .searchable(text: $searchText, prompt: "Geschäfte suchen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    NavigationLink {
                        GeschaeftChartView(session: session)
                    } label: {
                        Label("Diagramm", systemImage: "chart.dots.scatter")
                    }
                    Button {
                        showSessionAnalysis = true
                    } label: {
                        Label("KI-Analyse", systemImage: "brain")
                    }
                    Button {
                        Task { await loadGeschaefte() }
                    } label: {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                sortMenu
            }
            ToolbarItem(placement: .secondaryAction) {
                filterButton
            }
        }
        .sheet(isPresented: $showSessionAnalysis) {
            SessionAnalysisView(session: session)
        }
        .sheet(isPresented: $showFilterSheet) {
            GeschaeftFilterSheetView(
                availableGeschaeftstypen: availableGeschaeftstypen,
                availableRaete: availableRaete,
                availableDepartemente: availableDepartemente,
                availableStatus: availableStatus,
                filterGeschaeftstypen: $filterGeschaeftstypen,
                filterRat: $filterRat,
                filterDepartemente: $filterDepartemente,
                filterStatus: $filterStatus,
                filterNurAnalysierte: $filterNurAnalysierte
            )
            .presentationDetents([.medium, .large])
        }
        .refreshable {
            await loadGeschaefte()
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if session.geschaefte.isEmpty {
                await loadGeschaefte()
            }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(GeschaeftSortCriterion.allCases) { criterion in
                Button {
                    if sortCriterion == criterion {
                        sortAscending.toggle()
                    } else {
                        sortCriterion = criterion
                        sortAscending = true
                    }
                } label: {
                    HStack {
                        Label(criterion.label, systemImage: criterion.icon)
                        if sortCriterion == criterion {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            Label("Sortieren", systemImage: "arrow.up.arrow.down")
        }
    }

    // MARK: - Filter Button

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Label(
                activeFilterCount > 0 ? "Filter (\(activeFilterCount))" : "Filter",
                systemImage: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
    }

    // MARK: - List

    private var geschaeftList: some View {
        VStack(spacing: 0) {
            if activeFilterCount > 0 || sortCriterion != .nummer {
                activeFiltersBar
            }

            List(filteredAndSorted) { geschaeft in
                NavigationLink(value: geschaeft) {
                    GeschaeftRowView(geschaeft: geschaeft, sortCriterion: sortCriterion)
                }
            }
            .navigationDestination(for: Geschaeft.self) { geschaeft in
                GeschaeftDetailView(geschaeft: geschaeft)
            }
            .overlay {
                if filteredAndSorted.isEmpty && !session.geschaefte.isEmpty {
                    ContentUnavailableView(
                        "Keine Treffer",
                        systemImage: "magnifyingglass",
                        description: Text("Versuche andere Filter- oder Suchkriterien.")
                    )
                }
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding()
                }
            }
        }
    }

    // MARK: - Active Filters Bar

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort indicator
                if sortCriterion != .nummer {
                    chipView(
                        label: sortCriterion.label,
                        icon: sortAscending ? "chevron.up" : "chevron.down",
                        color: .blue
                    ) {
                        sortCriterion = .nummer
                        sortAscending = false
                    }
                }

                // Active filters as chips
                if !filterGeschaeftstypen.isEmpty {
                    chipView(
                        label: filterGeschaeftstypen.sorted().joined(separator: ", "),
                        icon: "tag",
                        color: .purple
                    ) {
                        filterGeschaeftstypen.removeAll()
                    }
                }
                if let rat = filterRat {
                    chipView(label: rat, icon: "building.columns", color: .teal) {
                        filterRat = nil
                    }
                }
                if !filterDepartemente.isEmpty {
                    chipView(
                        label: filterDepartemente.sorted().joined(separator: ", "),
                        icon: "briefcase",
                        color: .orange
                    ) {
                        filterDepartemente.removeAll()
                    }
                }
                if !filterStatus.isEmpty {
                    chipView(
                        label: filterStatus.sorted().joined(separator: ", "),
                        icon: "flag",
                        color: .green
                    ) {
                        filterStatus.removeAll()
                    }
                }
                if filterNurAnalysierte {
                    chipView(label: "Analysiert", icon: "brain", color: .purple) {
                        filterNurAnalysierte = false
                    }
                }

                // Result count
                Text("\(filteredAndSorted.count) Ergebnisse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chipView(label: String, icon: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption)
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Loading

    private func loadGeschaefte() async {
        isLoading = true
        errorMessage = nil
        do {
            let dtos = try await service.fetchGeschaefte(sessionID: session.id)
            let existingIDs = Set(session.geschaefte.map(\.id))
            for dto in dtos {
                if !existingIDs.contains(dto.ID) {
                    let geschaeft = Geschaeft(
                        id: dto.ID,
                        businessShortNumber: dto.BusinessShortNumber ?? "",
                        title: dto.Title ?? "Ohne Titel",
                        businessTypeName: dto.BusinessTypeName ?? "",
                        businessTypeAbbreviation: dto.BusinessTypeAbbreviation ?? "",
                        businessStatusText: dto.BusinessStatusText ?? "",
                        businessStatusDate: ODataDateParser.parse(dto.BusinessStatusDate),
                        submissionDate: ODataDateParser.parse(dto.SubmissionDate),
                        submittedBy: dto.SubmittedBy,
                        descriptionText: dto.Description,
                        submissionCouncilName: dto.SubmissionCouncilName,
                        responsibleDepartmentName: dto.ResponsibleDepartmentName,
                        responsibleDepartmentAbbreviation: dto.ResponsibleDepartmentAbbreviation,
                        tagNames: dto.TagNames,
                        session: session
                    )
                    modelContext.insert(geschaeft)
                }
            }
            try modelContext.save()
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }
}

// MARK: - Row View

struct GeschaeftRowView: View {
    let geschaeft: Geschaeft
    var sortCriterion: GeschaeftSortCriterion = .nummer

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "de_CH")
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(geschaeft.businessShortNumber)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(geschaeft.businessTypeAbbreviation)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.1))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())
            }
            Text(geschaeft.title)
                .font(.subheadline)
                .lineLimit(2)
            Text(geschaeft.businessStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Context line depending on sort criterion
            sortContextLine
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var sortContextLine: some View {
        switch sortCriterion {
        case .nummer, .titel, .geschaeftstyp:
            EmptyView()
        case .einreichedatum:
            if let date = geschaeft.submissionDate {
                Text("Eingereicht: \(dateFormatter.string(from: date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .linksRechts:
            analysisValueLine(value: geschaeft.linksRechts, format: "%+.2f", label: "Links/Rechts")
        case .konservativLiberal:
            analysisValueLine(value: geschaeft.konservativLiberal, format: "%+.2f", label: "Kons./Liberal")
        case .liberaleWirtschaft:
            analysisFactorLine(value: geschaeft.liberaleWirtschaft, label: "Lib. Wirtschaft")
        case .innovativerStandort:
            analysisFactorLine(value: geschaeft.innovativerStandort, label: "Inn. Standort")
        case .stromversorgung:
            analysisFactorLine(value: geschaeft.unabhaengigeStromversorgung, label: "Stromversorgung")
        case .staerkeResilienz:
            analysisFactorLine(value: geschaeft.staerkeResilienz, label: "Stärke/Resilienz")
        case .schlankerStaat:
            analysisFactorLine(value: geschaeft.schlankerStaat, label: "Schlanker Staat")
        }
    }

    private func analysisValueLine(value: Double?, format: String, label: String) -> some View {
        HStack(spacing: 4) {
            if let value {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: format, value))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(value < -0.1 ? .red : value > 0.1 ? .blue : .secondary)
            } else {
                Text("Nicht analysiert")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func analysisFactorLine(value: Double?, label: String) -> some View {
        HStack(spacing: 6) {
            if let value {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: value, total: 1.0)
                    .frame(width: 60)
                    .tint(factorColor(value))
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(factorColor(value))
            } else {
                Text("Nicht analysiert")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func factorColor(_ v: Double) -> Color {
        if v < 0.3 { return .red }
        if v < 0.6 { return .orange }
        return .green
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

// MARK: - Filter Sheet

struct GeschaeftFilterSheetView: View {
    let availableGeschaeftstypen: [String]
    let availableRaete: [String]
    let availableDepartemente: [String]
    let availableStatus: [String]

    @Binding var filterGeschaeftstypen: Set<String>
    @Binding var filterRat: String?
    @Binding var filterDepartemente: Set<String>
    @Binding var filterStatus: Set<String>
    @Binding var filterNurAnalysierte: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Geschäftstyp
                Section {
                    ForEach(availableGeschaeftstypen, id: \.self) { typ in
                        MultiSelectRow(
                            label: geschaeftstypDisplayName(typ),
                            isSelected: filterGeschaeftstypen.contains(typ),
                            color: geschaeftstypColor(typ)
                        ) {
                            toggleSet(&filterGeschaeftstypen, value: typ)
                        }
                    }
                } header: {
                    Label("Geschäftstyp", systemImage: "tag")
                }

                // Rat
                if !availableRaete.isEmpty {
                    Section {
                        ForEach(availableRaete, id: \.self) { rat in
                            SingleSelectRow(
                                label: rat,
                                isSelected: filterRat == rat
                            ) {
                                filterRat = filterRat == rat ? nil : rat
                            }
                        }
                    } header: {
                        Label("Rat", systemImage: "building.columns")
                    }
                }

                // Departement
                if !availableDepartemente.isEmpty {
                    Section {
                        ForEach(availableDepartemente, id: \.self) { dep in
                            MultiSelectRow(
                                label: dep,
                                isSelected: filterDepartemente.contains(dep),
                                color: .orange
                            ) {
                                toggleSet(&filterDepartemente, value: dep)
                            }
                        }
                    } header: {
                        Label("Departement", systemImage: "briefcase")
                    }
                }

                // Status
                if !availableStatus.isEmpty {
                    Section {
                        ForEach(availableStatus, id: \.self) { status in
                            MultiSelectRow(
                                label: status,
                                isSelected: filterStatus.contains(status),
                                color: .green
                            ) {
                                toggleSet(&filterStatus, value: status)
                            }
                        }
                    } header: {
                        Label("Status", systemImage: "flag")
                    }
                }

                // Toggles
                Section {
                    Toggle(isOn: $filterNurAnalysierte) {
                        Label("Nur analysierte", systemImage: "brain")
                    }
                } header: {
                    Label("Analyse", systemImage: "slider.horizontal.3")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Zurücksetzen") {
                        resetFilters()
                    }
                    .disabled(!hasActiveFilters)
                }
            }
        }
    }

    private var hasActiveFilters: Bool {
        !filterGeschaeftstypen.isEmpty
        || filterRat != nil
        || !filterDepartemente.isEmpty
        || !filterStatus.isEmpty
        || filterNurAnalysierte
    }

    private func resetFilters() {
        filterGeschaeftstypen.removeAll()
        filterRat = nil
        filterDepartemente.removeAll()
        filterStatus.removeAll()
        filterNurAnalysierte = false
    }

    private func toggleSet<T: Hashable>(_ set: inout Set<T>, value: T) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func geschaeftstypDisplayName(_ abbreviation: String) -> String {
        switch abbreviation {
        case "BRG": return "Bundesratsgeschäft (BRG)"
        case "Mo.": return "Motion (Mo.)"
        case "Po.": return "Postulat (Po.)"
        case "Pa.Iv.": return "Parlamentarische Initiative (Pa.Iv.)"
        case "Kt.Iv.": return "Standesinitiative (Kt.Iv.)"
        case "Ip.": return "Interpellation (Ip.)"
        case "Fra.": return "Fragestunde (Fra.)"
        default: return abbreviation
        }
    }

    private func geschaeftstypColor(_ abbreviation: String) -> Color {
        switch abbreviation {
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
