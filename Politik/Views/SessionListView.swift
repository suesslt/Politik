import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startDate, order: .reverse) private var sessions: [Session]
    @Query private var alleGeschaefte: [Geschaeft]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSyncSheet = false
    @State private var searchText = ""

    private let service = ParlamentService()

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private var searchResults: [Geschaeft] {
        guard isSearching else { return [] }
        let query = searchText.lowercased()
        return alleGeschaefte.filter {
            $0.title.lowercased().contains(query)
            || $0.businessShortNumber.lowercased().contains(query)
            || $0.businessTypeName.lowercased().contains(query)
            || ($0.submittedBy?.lowercased().contains(query) ?? false)
            || ($0.tagNames?.lowercased().contains(query) ?? false)
            || ($0.responsibleDepartmentName?.lowercased().contains(query) ?? false)
            || ($0.descriptionText?.lowercased().contains(query) ?? false)
        }
        .sorted { $0.businessShortNumber > $1.businessShortNumber }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    searchResultsList
                } else if sessions.isEmpty && isLoading {
                    ProgressView("Sessionen werden geladen…")
                } else if sessions.isEmpty {
                    ContentUnavailableView(
                        "Keine Sessionen",
                        systemImage: "building.columns",
                        description: Text("Ziehe nach unten, um Sessionen zu laden.")
                    )
                } else {
                    sessionList
                }
            }
            .navigationTitle("Sessionen")
            .searchable(text: $searchText, prompt: "Alle Geschäfte durchsuchen…")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showSyncSheet = true
                        } label: {
                            Label("Synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(sessions.isEmpty)
                        Button {
                            Task { await loadSessions() }
                        } label: {
                            Label("Aktualisieren", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .sheet(isPresented: $showSyncSheet) {
                SessionSyncView(sessions: sessions)
            }
            .refreshable {
                await loadSessions()
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                if sessions.isEmpty {
                    await loadSessions()
                }
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        Group {
            if searchResults.isEmpty {
                ContentUnavailableView(
                    "Keine Treffer",
                    systemImage: "magnifyingglass",
                    description: Text("Kein Geschäft passt zu «\(searchText)».")
                )
            } else {
                List {
                    Section {
                        ForEach(searchResults) { geschaeft in
                            NavigationLink(value: geschaeft) {
                                GeschaeftSearchRowView(geschaeft: geschaeft)
                            }
                        }
                    } header: {
                        Text("\(searchResults.count) Treffer")
                    }
                }
                .navigationDestination(for: Geschaeft.self) { geschaeft in
                    GeschaeftDetailView(geschaeft: geschaeft)
                }
            }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List(sessions) { session in
            NavigationLink(value: session) {
                SessionRowView(session: session)
            }
        }
        .navigationDestination(for: Session.self) { session in
            GeschaeftListView(session: session)
        }
    }

    private func loadSessions() async {
        isLoading = true
        errorMessage = nil
        do {
            let dtos = try await service.fetchSessions()
            for dto in dtos {
                let existing = sessions.first { $0.id == dto.ID }
                if existing == nil {
                    let session = Session(
                        id: dto.ID,
                        sessionNumber: dto.SessionNumber ?? 0,
                        sessionName: dto.SessionName ?? "Unbekannt",
                        abbreviation: dto.Abbreviation ?? "",
                        startDate: ODataDateParser.parse(dto.StartDate),
                        endDate: ODataDateParser.parse(dto.EndDate),
                        title: dto.Title ?? "",
                        type: dto.SessionType ?? 0,
                        typeName: dto.TypeName ?? "",
                        legislativePeriodNumber: dto.LegislativePeriodNumber ?? 0
                    )
                    modelContext.insert(session)
                }
            }
            try modelContext.save()
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }
}

struct SessionRowView: View {
    let session: Session

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "de_CH")
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.sessionName)
                    .font(.headline)
                if session.isSynced {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            HStack {
                Text(session.abbreviation)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                if session.type == 3 {
                    Text("Sondersession")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            if let start = session.startDate {
                Text(dateFormatter.string(from: start))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("\(session.geschaefte.count) Geschäfte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastSync = session.lastSyncDate {
                    Text("· \(lastSync, style: .relative) her")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Search Row

struct GeschaeftSearchRowView: View {
    let geschaeft: Geschaeft

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
            HStack(spacing: 6) {
                Text(geschaeft.businessStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let sessionName = geschaeft.session?.sessionName {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(sessionName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
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
