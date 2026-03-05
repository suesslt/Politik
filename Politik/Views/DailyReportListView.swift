import SwiftUI
import SwiftData

struct DailyReportListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startDate, order: .reverse) private var sessions: [Session]
    @Query(sort: \DailyReport.createdAt, order: .reverse) private var reports: [DailyReport]

    @State private var selectedSession: Session?
    @State private var selectedDate = Date()
    @State private var reportService = DailyReportService()
    @State private var errorMessage: String?
    @State private var generatedReport: DailyReport?
    @State private var isLoading = false

    private let service = ParlamentService()

    var body: some View {
        NavigationStack {
            List {
                generateSection
                reportListSection
            }
            .navigationTitle("Tagesberichte")
            .navigationDestination(for: DailyReport.self) { report in
                DailyReportDetailView(report: report)
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
                if selectedSession == nil {
                    selectedSession = sessions.first
                }
            }
        }
    }

    // MARK: - Generate Section

    private var generateSection: some View {
        Section {
            Picker("Session", selection: $selectedSession) {
                Text("Bitte wählen").tag(nil as Session?)
                ForEach(sessions) { session in
                    Text(session.sessionName).tag(session as Session?)
                }
            }

            DatePicker("Datum", selection: $selectedDate, displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "de_CH"))

            Button {
                Task { await generateReport() }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusText)
                    } else {
                        Label("Bericht erstellen", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .disabled(selectedSession == nil || isGenerating)
        } header: {
            Text("Neuer Bericht")
        } footer: {
            Text("Die Session-Daten werden vor der Berichterstellung aktualisiert.")
        }
    }

    // MARK: - Reports List

    private var reportListSection: some View {
        Section {
            if reports.isEmpty {
                ContentUnavailableView(
                    "Keine Berichte",
                    systemImage: "doc.text",
                    description: Text("Erstelle einen Tagesbericht über das Formular oben.")
                )
            } else {
                ForEach(reports) { report in
                    NavigationLink(value: report) {
                        DailyReportRowView(report: report)
                    }
                }
                .onDelete(perform: deleteReports)
            }
        } header: {
            Text("Bisherige Berichte (\(reports.count))")
        }
    }

    // MARK: - State Helpers

    private var isGenerating: Bool {
        reportService.phase != .idle && reportService.phase != .completed && reportService.phase != .error(message: "")
    }

    private var statusText: String {
        switch reportService.phase {
        case .idle: return ""
        case .syncing: return "Daten synchronisieren…"
        case .generating: return "Bericht wird erstellt…"
        case .completed: return "Fertig"
        case .error(let msg): return msg
        }
    }

    // MARK: - Actions

    private func generateReport() async {
        guard let session = selectedSession else { return }
        errorMessage = nil

        do {
            let report = try await reportService.generateReport(
                session: session,
                reportDate: selectedDate,
                modelContext: modelContext
            )
            generatedReport = report
            reportService.reset()
        } catch {
            errorMessage = error.localizedDescription
            reportService.reset()
        }
    }

    private func deleteReports(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(reports[index])
        }
        try? modelContext.save()
    }

    private func loadSessions() async {
        isLoading = true
        do {
            let dtos = try await service.fetchSessions()
            for dto in dtos {
                guard !sessions.contains(where: { $0.id == dto.ID }) else { continue }
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
            try modelContext.save()
        } catch {
            // Sessions already loaded from local DB
        }
        isLoading = false
    }
}

// MARK: - Row View

struct DailyReportRowView: View {
    let report: DailyReport

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "de_CH")
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_CH")
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateFormatter.string(from: report.reportDate))
                .font(.headline)
            Text(report.sessionName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Erstellt: \(timeFormatter.string(from: report.createdAt))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
