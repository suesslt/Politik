import SwiftUI
import SwiftData

// MARK: - Sort & Filter Types

enum ParlSortCriterion: String, CaseIterable, Identifiable {
    case name
    case birthDate
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
        case .name: "Name"
        case .birthDate: "Geburtsdatum"
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
        case .name: "textformat.abc"
        case .birthDate: "calendar"
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

enum Sprachregion: String, CaseIterable, Identifiable {
    case deutsch = "Deutschschweiz"
    case franzoesisch = "Romandie"
    case italienisch = "Svizzera italiana"

    var id: Self { self }

    static func fromCanton(_ canton: String?) -> Sprachregion? {
        guard let canton else { return nil }
        switch canton {
        case "AG", "AI", "AR", "BL", "BS", "GL", "GR", "LU",
             "NW", "OW", "SG", "SH", "SO", "SZ", "TG", "UR", "ZG", "ZH":
            return .deutsch
        case "GE", "JU", "NE", "VD":
            return .franzoesisch
        case "TI":
            return .italienisch
        case "BE", "FR", "VS":
            // Bilingual cantons — assign to Deutsch for simplicity,
            // but users may want separate handling
            return .deutsch
        default:
            return nil
        }
    }
}

// MARK: - Main View

struct ParlamentarierListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Parlamentarier.lastName) private var parlamentarier: [Parlamentarier]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showAnalysis = false
    @State private var showFilterSheet = false

    // Sort state
    @State private var sortCriterion: ParlSortCriterion = .name
    @State private var sortAscending: Bool = true

    // Filter state
    @State private var filterFraktionen: Set<String> = []
    @State private var filterKantone: Set<String> = []
    @State private var filterRat: String?
    @State private var filterSprachregionen: Set<Sprachregion> = []
    @State private var filterNurAktive: Bool = false
    @State private var filterNurAnalysierte: Bool = false

    private let service = ParlamentService()

    // MARK: - Derived Data

    private var availableFraktionen: [String] {
        Set(parlamentarier.compactMap(\.parlGroupAbbreviation)).sorted()
    }

    private var availableKantone: [String] {
        Set(parlamentarier.compactMap(\.cantonAbbreviation)).sorted()
    }

    private var availableRaete: [String] {
        Set(parlamentarier.compactMap(\.councilName)).sorted()
    }

    private var activeFilterCount: Int {
        var count = 0
        if !filterFraktionen.isEmpty { count += 1 }
        if !filterKantone.isEmpty { count += 1 }
        if filterRat != nil { count += 1 }
        if !filterSprachregionen.isEmpty { count += 1 }
        if filterNurAktive { count += 1 }
        if filterNurAnalysierte { count += 1 }
        return count
    }

    private var filteredAndSorted: [Parlamentarier] {
        var result = parlamentarier

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.fullName.lowercased().contains(query)
                || ($0.partyAbbreviation?.lowercased().contains(query) ?? false)
                || ($0.cantonAbbreviation?.lowercased().contains(query) ?? false)
                || ($0.parlGroupAbbreviation?.lowercased().contains(query) ?? false)
                || ($0.cantonName?.lowercased().contains(query) ?? false)
                || ($0.partyName?.lowercased().contains(query) ?? false)
            }
        }

        // Filters
        if !filterFraktionen.isEmpty {
            result = result.filter { filterFraktionen.contains($0.parlGroupAbbreviation ?? "") }
        }
        if !filterKantone.isEmpty {
            result = result.filter { filterKantone.contains($0.cantonAbbreviation ?? "") }
        }
        if let rat = filterRat {
            result = result.filter { $0.councilName == rat }
        }
        if !filterSprachregionen.isEmpty {
            result = result.filter { person in
                if let region = Sprachregion.fromCanton(person.cantonAbbreviation) {
                    return filterSprachregionen.contains(region)
                }
                return false
            }
        }
        if filterNurAktive {
            result = result.filter(\.isActive)
        }
        if filterNurAnalysierte {
            result = result.filter(\.hasAnalysis)
        }

        // Sort
        result.sort { a, b in
            let comparison: Bool
            switch sortCriterion {
            case .name:
                comparison = a.lastName.localizedCompare(b.lastName) == .orderedAscending
            case .birthDate:
                comparison = (a.dateOfBirth ?? .distantPast) < (b.dateOfBirth ?? .distantPast)
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
        NavigationStack {
            Group {
                if parlamentarier.isEmpty && isLoading {
                    ProgressView("Parlamentarier werden geladen…")
                } else if parlamentarier.isEmpty {
                    ContentUnavailableView(
                        "Keine Parlamentarier",
                        systemImage: "person.3",
                        description: Text("Ziehe nach unten, um Parlamentarier zu laden.")
                    )
                } else {
                    parlamentarierList
                }
            }
            .navigationTitle("Parlamentarier")
            .searchable(text: $searchText, prompt: "Name, Partei, Kanton…")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            ParlamentarierChartView()
                        } label: {
                            Label("Diagramm", systemImage: "chart.dots.scatter")
                        }
                        Button {
                            showAnalysis = true
                        } label: {
                            Label("KI-Analyse", systemImage: "brain")
                        }
                        Button {
                            Task { await loadParlamentarier() }
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
            .sheet(isPresented: $showAnalysis) {
                ParlamentarierAnalysisView()
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(
                    availableFraktionen: availableFraktionen,
                    availableKantone: availableKantone,
                    availableRaete: availableRaete,
                    filterFraktionen: $filterFraktionen,
                    filterKantone: $filterKantone,
                    filterRat: $filterRat,
                    filterSprachregionen: $filterSprachregionen,
                    filterNurAktive: $filterNurAktive,
                    filterNurAnalysierte: $filterNurAnalysierte
                )
                .presentationDetents([.medium, .large])
            }
            .refreshable {
                await loadParlamentarier()
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                if parlamentarier.isEmpty {
                    await loadParlamentarier()
                }
            }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(ParlSortCriterion.allCases) { criterion in
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

    private var parlamentarierList: some View {
        VStack(spacing: 0) {
            if activeFilterCount > 0 || sortCriterion != .name {
                activeFiltersBar
            }

            List(filteredAndSorted) { person in
                NavigationLink(value: person) {
                    ParlamentarierRowView(parlamentarier: person, sortCriterion: sortCriterion)
                }
            }
            .navigationDestination(for: Parlamentarier.self) { person in
                ParlamentarierDetailView(parlamentarier: person)
            }
            .overlay {
                if filteredAndSorted.isEmpty && !parlamentarier.isEmpty {
                    ContentUnavailableView(
                        "Keine Treffer",
                        systemImage: "magnifyingglass",
                        description: Text("Versuche andere Filter- oder Suchkriterien.")
                    )
                }
            }
        }
    }

    // MARK: - Active Filters Bar

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort indicator
                if sortCriterion != .name {
                    chipView(
                        label: sortCriterion.label,
                        icon: sortAscending ? "chevron.up" : "chevron.down",
                        color: .blue
                    ) {
                        sortCriterion = .name
                        sortAscending = true
                    }
                }

                // Active filters as chips
                if !filterFraktionen.isEmpty {
                    chipView(
                        label: filterFraktionen.sorted().joined(separator: ", "),
                        icon: "person.3",
                        color: .purple
                    ) {
                        filterFraktionen.removeAll()
                    }
                }
                if !filterKantone.isEmpty {
                    chipView(
                        label: filterKantone.sorted().joined(separator: ", "),
                        icon: "map",
                        color: .orange
                    ) {
                        filterKantone.removeAll()
                    }
                }
                if let rat = filterRat {
                    chipView(label: rat, icon: "building.columns", color: .teal) {
                        filterRat = nil
                    }
                }
                if !filterSprachregionen.isEmpty {
                    chipView(
                        label: filterSprachregionen.map(\.rawValue).sorted().joined(separator: ", "),
                        icon: "globe",
                        color: .green
                    ) {
                        filterSprachregionen.removeAll()
                    }
                }
                if filterNurAktive {
                    chipView(label: "Nur Aktive", icon: "checkmark.circle", color: .green) {
                        filterNurAktive = false
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

    private func loadParlamentarier() async {
        isLoading = true
        errorMessage = nil
        do {
            let dtos = try await service.fetchAllParlamentarier()
            let existingNumbers = Set(parlamentarier.map(\.personNumber))
            for dto in dtos {
                let personNumber = dto.PersonNumber ?? dto.ID ?? 0
                guard personNumber != 0, !existingNumbers.contains(personNumber) else { continue }
                let person = Parlamentarier(
                    personNumber: personNumber,
                    firstName: dto.FirstName ?? "",
                    lastName: dto.LastName ?? "",
                    partyAbbreviation: dto.PartyAbbreviation,
                    parlGroupAbbreviation: dto.ParlGroupAbbreviation,
                    cantonAbbreviation: dto.CantonAbbreviation,
                    councilName: dto.CouncilName,
                    councilAbbreviation: dto.CouncilAbbreviation,
                    isActive: dto.Active ?? true
                )
                modelContext.insert(person)
            }
            try modelContext.save()
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }
}

// MARK: - Row View

struct ParlamentarierRowView: View {
    let parlamentarier: Parlamentarier
    var sortCriterion: ParlSortCriterion = .name

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "de_CH")
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parlamentarier.fullName)
                    .font(.headline)
                Spacer()
                if let canton = parlamentarier.cantonAbbreviation {
                    Text(canton)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                if let party = parlamentarier.partyAbbreviation {
                    Text(party)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                if let group = parlamentarier.parlGroupAbbreviation {
                    Text(group)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(parlGroupColor(group).opacity(0.15))
                        .foregroundStyle(parlGroupColor(group))
                        .clipShape(Capsule())
                }
                if let council = parlamentarier.councilAbbreviation {
                    Text(council)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !parlamentarier.isActive {
                    Text("Inaktiv")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.1))
                        .foregroundStyle(.gray)
                        .clipShape(Capsule())
                }
            }

            // Context line depending on sort criterion
            sortContextLine
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var sortContextLine: some View {
        switch sortCriterion {
        case .name:
            if !parlamentarier.geschaefte.isEmpty {
                Text("\(parlamentarier.geschaefte.count) Geschäfte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .birthDate:
            if let dob = parlamentarier.dateOfBirth {
                Text("Geb. \(dateFormatter.string(from: dob))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .linksRechts:
            analysisValueLine(value: parlamentarier.linksRechts, format: "%+.2f", label: "Links/Rechts")
        case .konservativLiberal:
            analysisValueLine(value: parlamentarier.konservativLiberal, format: "%+.2f", label: "Kons./Liberal")
        case .liberaleWirtschaft:
            analysisFactorLine(value: parlamentarier.liberaleWirtschaft, label: "Lib. Wirtschaft")
        case .innovativerStandort:
            analysisFactorLine(value: parlamentarier.innovativerStandort, label: "Inn. Standort")
        case .stromversorgung:
            analysisFactorLine(value: parlamentarier.unabhaengigeStromversorgung, label: "Stromversorgung")
        case .staerkeResilienz:
            analysisFactorLine(value: parlamentarier.staerkeResilienz, label: "Stärke/Resilienz")
        case .schlankerStaat:
            analysisFactorLine(value: parlamentarier.schlankerStaat, label: "Schlanker Staat")
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
}

// MARK: - Filter Sheet

struct FilterSheetView: View {
    let availableFraktionen: [String]
    let availableKantone: [String]
    let availableRaete: [String]

    @Binding var filterFraktionen: Set<String>
    @Binding var filterKantone: Set<String>
    @Binding var filterRat: String?
    @Binding var filterSprachregionen: Set<Sprachregion>
    @Binding var filterNurAktive: Bool
    @Binding var filterNurAnalysierte: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Fraktion
                Section {
                    ForEach(availableFraktionen, id: \.self) { fraktion in
                        MultiSelectRow(
                            label: "\(parlGroupDisplayName(fraktion)) (\(fraktion))",
                            isSelected: filterFraktionen.contains(fraktion),
                            color: parlGroupColor(fraktion)
                        ) {
                            toggleSet(&filterFraktionen, value: fraktion)
                        }
                    }
                } header: {
                    Label("Fraktion", systemImage: "person.3")
                }

                // Rat
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

                // Sprachregion
                Section {
                    ForEach(Sprachregion.allCases) { region in
                        MultiSelectRow(
                            label: region.rawValue,
                            isSelected: filterSprachregionen.contains(region),
                            color: .green
                        ) {
                            toggleSet(&filterSprachregionen, value: region)
                        }
                    }
                } header: {
                    Label("Sprachregion", systemImage: "globe")
                }

                // Kanton
                Section {
                    kantonGrid
                } header: {
                    Label("Kanton", systemImage: "map")
                }

                // Toggles
                Section {
                    Toggle(isOn: $filterNurAktive) {
                        Label("Nur aktive Mitglieder", systemImage: "checkmark.circle")
                    }
                    Toggle(isOn: $filterNurAnalysierte) {
                        Label("Nur analysierte", systemImage: "brain")
                    }
                } header: {
                    Label("Status", systemImage: "slider.horizontal.3")
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

    private var kantonGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(availableKantone, id: \.self) { kanton in
                Button {
                    toggleSet(&filterKantone, value: kanton)
                } label: {
                    Text(kanton)
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            filterKantone.contains(kanton)
                            ? Color.orange
                            : Color.secondary.opacity(0.1)
                        )
                        .foregroundStyle(
                            filterKantone.contains(kanton)
                            ? .white
                            : .primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hasActiveFilters: Bool {
        !filterFraktionen.isEmpty
        || !filterKantone.isEmpty
        || filterRat != nil
        || !filterSprachregionen.isEmpty
        || filterNurAktive
        || filterNurAnalysierte
    }

    private func resetFilters() {
        filterFraktionen.removeAll()
        filterKantone.removeAll()
        filterRat = nil
        filterSprachregionen.removeAll()
        filterNurAktive = false
        filterNurAnalysierte = false
    }

    private func toggleSet<T: Hashable>(_ set: inout Set<T>, value: T) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func parlGroupDisplayName(_ abbreviation: String) -> String {
        switch abbreviation {
        case "S": return "SP"
        case "G": return "Grüne"
        case "GL": return "GLP"
        case "V": return "SVP"
        case "RL": return "FDP"
        case "M-E", "M": return "Mitte"
        case "BD": return "BDP"
        default: return abbreviation
        }
    }
}

// MARK: - Reusable Filter Rows

struct MultiSelectRow: View {
    let label: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }
}

struct SingleSelectRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }
}
