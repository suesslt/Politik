import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service = DataExportImportService()

    // Export
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false

    // Import
    @State private var showFileImporter = false
    @State private var importPreview: ExportContainer?
    @State private var importData: Data?
    @State private var showImportConfirmation = false

    // API Key
    @AppStorage("claude_api_key") private var apiKey: String = ""

    // Counts
    @Query private var sessions: [Session]
    @Query private var geschaefte: [Geschaeft]
    @Query private var parlamentarier: [Parlamentarier]
    @Query private var wortmeldungen: [Wortmeldung]
    @Query private var abstimmungen: [Abstimmung]
    @Query private var stimmabgaben: [Stimmabgabe]
    @Query private var personInterests: [PersonInterest]
    @Query private var personOccupations: [PersonOccupation]
    @Query private var propositions: [Proposition]

    // Date fix
    @State private var isResettingDates = false
    @State private var dateResetMessage: String?

    var body: some View {
        NavigationStack {
            List {
                apiKeySection
                currentDataSection
                maintenanceSection
                exportSection
                importSection
                statusSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Datenverwaltung")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheetView(url: url)
                }
            }
            .alert("Daten importieren?", isPresented: $showImportConfirmation) {
                Button("Abbrechen", role: .cancel) {
                    importPreview = nil
                    importData = nil
                }
                Button("Importieren", role: .destructive) {
                    performImport()
                }
            } message: {
                if let preview = importPreview {
                    Text("""
                    Achtung: Alle bestehenden Daten werden gelöscht und ersetzt!

                    Import enthält:
                    • \(preview.sessions.count) Sessionen
                    • \(preview.geschaefte.count) Geschäfte
                    • \(preview.parlamentarier.count) Parlamentarier
                    • \(preview.wortmeldungen.count) Wortmeldungen
                    • \(preview.abstimmungen.count) Abstimmungen
                    • \(preview.stimmabgaben.count) Stimmabgaben
                    • \(preview.personInterests.count) Interessen
                    • \(preview.personOccupations.count) Berufe
                    • \((preview.propositions ?? []).count) Propositionen
                    """)
                }
            }
        }
    }

    // MARK: - API Key

    private var apiKeySection: some View {
        Section {
            SecureField("API-Key eingeben", text: $apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()

            if !apiKey.isEmpty {
                HStack {
                    Label("Key gespeichert", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button(role: .destructive) {
                        apiKey = ""
                    } label: {
                        Label("Löschen", systemImage: "trash")
                            .font(.caption)
                    }
                }
            } else {
                Label("Kein API-Key konfiguriert", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Label("Claude AI", systemImage: "brain")
        } footer: {
            Text("Der API-Key wird lokal gespeichert und für die KI-Analyse verwendet.")
        }
    }

    // MARK: - Current Data

    private var currentDataSection: some View {
        Section {
            LabeledContent("Sessionen", value: "\(sessions.count)")
            LabeledContent("Geschäfte", value: "\(geschaefte.count)")
            LabeledContent("Parlamentarier", value: "\(parlamentarier.count)")
            LabeledContent("Wortmeldungen", value: "\(wortmeldungen.count)")
            LabeledContent("Abstimmungen", value: "\(abstimmungen.count)")
            LabeledContent("Stimmabgaben", value: "\(stimmabgaben.count)")
            LabeledContent("Interessen", value: "\(personInterests.count)")
            LabeledContent("Berufe", value: "\(personOccupations.count)")
            LabeledContent("Propositionen", value: "\(propositions.count)")
        } header: {
            Label("Aktuelle Daten", systemImage: "cylinder.split.1x2")
        }
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        Section {
            Button {
                resetDetailFlags()
            } label: {
                Label("Geburtsdaten neu laden", systemImage: "arrow.clockwise")
            }
            .disabled(isResettingDates)

            if let message = dateResetMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } header: {
            Label("Wartung", systemImage: "wrench.and.screwdriver")
        } footer: {
            Text("Setzt das Detail-Flag aller Parlamentarier zurück, damit beim nächsten Öffnen die Daten (inkl. Geburtsdatum) neu vom Server geladen werden.")
        }
    }

    private func resetDetailFlags() {
        isResettingDates = true
        var count = 0
        for p in parlamentarier {
            if p.isDetailLoaded {
                p.isDetailLoaded = false
                count += 1
            }
        }
        try? modelContext.save()
        dateResetMessage = "\(count) Parlamentarier zurückgesetzt"
        isResettingDates = false
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Button {
                performExport()
            } label: {
                Label("Daten exportieren (JSON)", systemImage: "square.and.arrow.up")
            }
            .disabled(isProcessing)
        } header: {
            Label("Export", systemImage: "arrow.up.doc")
        } footer: {
            Text("Exportiert alle Daten als JSON-Datei. Relationships werden über IDs verknüpft.")
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            Button {
                showFileImporter = true
            } label: {
                Label("JSON-Datei importieren", systemImage: "square.and.arrow.down")
            }
            .disabled(isProcessing)
        } header: {
            Label("Import", systemImage: "arrow.down.doc")
        } footer: {
            Text("Importiert eine zuvor exportierte JSON-Datei. Bestehende Daten werden dabei vollständig ersetzt.")
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        switch service.phase {
        case .idle:
            EmptyView()
        case .exporting:
            Section("Status") {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Exportiere Daten…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .importing(let step):
            Section("Status") {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .completed(let message):
            Section("Status") {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .error(let message):
            Section("Status") {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var isProcessing: Bool {
        switch service.phase {
        case .exporting, .importing: return true
        default: return false
        }
    }

    // MARK: - Actions

    private func performExport() {
        do {
            let data = try service.exportAll(modelContext: modelContext)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let filename = "Politik_Export_\(formatter.string(from: Date())).json"

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: tempURL)

            exportedFileURL = tempURL
            showShareSheet = true
        } catch {
            service.phase = .error(message: "Export fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    service.phase = .error(message: "Kein Zugriff auf die Datei")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url)
                let preview = try service.previewImport(from: data)
                importData = data
                importPreview = preview
                showImportConfirmation = true
            } catch {
                service.phase = .error(message: "Datei konnte nicht gelesen werden: \(error.localizedDescription)")
            }
        case .failure(let error):
            service.phase = .error(message: "Dateiauswahl fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func performImport() {
        guard let data = importData else { return }
        do {
            try service.importAll(from: data, modelContext: modelContext)
        } catch {
            service.phase = .error(message: "Import fehlgeschlagen: \(error.localizedDescription)")
        }
        importData = nil
        importPreview = nil
    }
}

// MARK: - Share Sheet (UIKit wrapper)

struct ShareSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
