import SwiftUI
import SwiftData

// MARK: - Sort Criterion

enum WortmeldungSortCriterion: String, CaseIterable, Identifiable {
    case datum
    case sprecher
    case geschaeft

    var id: Self { self }

    var label: String {
        switch self {
        case .datum: "Datum"
        case .sprecher: "Sprecher"
        case .geschaeft: "Geschäft"
        }
    }

    var icon: String {
        switch self {
        case .datum: "calendar"
        case .sprecher: "person"
        case .geschaeft: "doc.text"
        }
    }
}

// MARK: - Main View

struct WortmeldungListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wortmeldung> { $0.type == 1 })
    private var alleWortmeldungen: [Wortmeldung]

    @State private var searchText = ""
    @State private var showFilterSheet = false

    // Sort state
    @State private var sortCriterion: WortmeldungSortCriterion = .datum
    @State private var sortAscending: Bool = false

    // Filter state
    @State private var filterFraktionen: Set<String> = []
    @State private var filterKantone: Set<String> = []
    @State private var filterRat: String?

    // MARK: - Derived Data

    private var availableFraktionen: [String] {
        Set(alleWortmeldungen.compactMap(\.parlGroupAbbreviation)).sorted()
    }

    private var availableKantone: [String] {
        Set(alleWortmeldungen.compactMap(\.cantonAbbreviation)).sorted()
    }

    private var availableRaete: [String] {
        Set(alleWortmeldungen.compactMap(\.councilName)).sorted()
    }

    private var activeFilterCount: Int {
        var count = 0
        if !filterFraktionen.isEmpty { count += 1 }
        if !filterKantone.isEmpty { count += 1 }
        if filterRat != nil { count += 1 }
        return count
    }

    private var filteredAndSorted: [Wortmeldung] {
        var result = alleWortmeldungen

        // Full-text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.plainText.lowercased().contains(query)
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

        // Sort
        result.sort { a, b in
            let comparison: Bool
            switch sortCriterion {
            case .datum:
                comparison = (a.meetingDate ?? "") < (b.meetingDate ?? "")
            case .sprecher:
                comparison = a.speakerFullName.localizedCompare(b.speakerFullName) == .orderedAscending
            case .geschaeft:
                comparison = (a.geschaeft?.title ?? "").localizedCompare(b.geschaeft?.title ?? "") == .orderedAscending
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if alleWortmeldungen.isEmpty {
                    ContentUnavailableView(
                        "Keine Wortmeldungen",
                        systemImage: "text.quote",
                        description: Text("Synchronisiere zuerst Sessionen, um Wortmeldungen zu laden.")
                    )
                } else {
                    wortmeldungList
                }
            }
            .navigationTitle("Wortmeldungen")
            .searchable(text: $searchText, prompt: "Volltext durchsuchen…")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    sortMenu
                }
                ToolbarItem(placement: .secondaryAction) {
                    filterButton
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                WortmeldungFilterSheetView(
                    availableFraktionen: availableFraktionen,
                    availableKantone: availableKantone,
                    availableRaete: availableRaete,
                    filterFraktionen: $filterFraktionen,
                    filterKantone: $filterKantone,
                    filterRat: $filterRat
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(WortmeldungSortCriterion.allCases) { criterion in
                Button {
                    if sortCriterion == criterion {
                        sortAscending.toggle()
                    } else {
                        sortCriterion = criterion
                        sortAscending = criterion == .sprecher || criterion == .geschaeft
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

    private var wortmeldungList: some View {
        VStack(spacing: 0) {
            if activeFilterCount > 0 || sortCriterion != .datum {
                activeFiltersBar
            }

            List(filteredAndSorted) { wortmeldung in
                NavigationLink(value: wortmeldung) {
                    WortmeldungListRowView(wortmeldung: wortmeldung)
                }
            }
            .navigationDestination(for: Wortmeldung.self) { wortmeldung in
                WortmeldungDetailView(wortmeldung: wortmeldung)
            }
            .overlay {
                if filteredAndSorted.isEmpty && !alleWortmeldungen.isEmpty {
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
                if sortCriterion != .datum {
                    chipView(
                        label: sortCriterion.label,
                        icon: sortAscending ? "chevron.up" : "chevron.down",
                        color: .blue
                    ) {
                        sortCriterion = .datum
                        sortAscending = false
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
}

// MARK: - Row View

struct WortmeldungListRowView: View {
    let wortmeldung: Wortmeldung

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Speaker line
            HStack {
                Text(wortmeldung.speakerFullName)
                    .font(.headline)
                Spacer()
                if let group = wortmeldung.parlGroupAbbreviation {
                    Text(group)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(parlGroupColor(group).opacity(0.15))
                        .foregroundStyle(parlGroupColor(group))
                        .clipShape(Capsule())
                }
                if let canton = wortmeldung.cantonAbbreviation {
                    Text(canton)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Geschäft
            if let geschaeft = wortmeldung.geschaeft {
                HStack(spacing: 4) {
                    Text(geschaeft.businessShortNumber)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(geschaeft.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Date
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

// MARK: - Filter Sheet

struct WortmeldungFilterSheetView: View {
    let availableFraktionen: [String]
    let availableKantone: [String]
    let availableRaete: [String]

    @Binding var filterFraktionen: Set<String>
    @Binding var filterKantone: Set<String>
    @Binding var filterRat: String?

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

                // Kanton
                if !availableKantone.isEmpty {
                    Section {
                        kantonGrid
                    } header: {
                        Label("Kanton", systemImage: "map")
                    }
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
    }

    private func resetFilters() {
        filterFraktionen.removeAll()
        filterKantone.removeAll()
        filterRat = nil
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
