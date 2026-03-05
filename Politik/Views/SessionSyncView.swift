import SwiftUI
import SwiftData

struct SessionSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var syncService = SessionSyncService()
    @State private var selectedSessionIDs: Set<Int> = []
    @State private var syncTask: Task<Void, Never>?

    let sessions: [Session]

    var body: some View {
        NavigationStack {
            Group {
                switch syncService.phase {
                case .idle:
                    sessionSelectionView
                case .completed, .cancelled:
                    resultView
                default:
                    progressView
                }
            }
            .navigationTitle("Daten synchronisieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if syncService.isSyncing {
                        Button("Abbrechen") {
                            syncTask?.cancel()
                        }
                        .foregroundStyle(.red)
                    } else {
                        Button("Schliessen") {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(syncService.isSyncing)
        }
    }

    // MARK: - Session Selection

    private var sessionSelectionView: some View {
        List {
            Section {
                ForEach(sessions) { session in
                    Button {
                        toggleSelection(session.id)
                    } label: {
                        HStack {
                            Image(systemName: selectedSessionIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedSessionIDs.contains(session.id) ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(session.sessionName)
                                        .font(.subheadline)
                                    if session.isSynced {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text("\(session.geschaefte.count) Geschäfte")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let lastSync = session.lastSyncDate {
                                        Text("· Sync: \(lastSync, style: .relative) her")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            } header: {
                Text("Sessionen auswählen")
            } footer: {
                if !selectedSessionIDs.isEmpty {
                    let totalGeschaefte = sessions.filter { selectedSessionIDs.contains($0.id) }.reduce(0) { $0 + $1.geschaefte.count }
                    Text("~\(totalGeschaefte > 0 ? totalGeschaefte * 5 : selectedSessionIDs.count * 250) API-Aufrufe geschätzt")
                }
            }

            Section {
                HStack {
                    Button("Alle auswählen") {
                        selectedSessionIDs = Set(sessions.map(\.id))
                    }
                    .font(.caption)
                    Spacer()
                    Button("Keine") {
                        selectedSessionIDs.removeAll()
                    }
                    .font(.caption)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                startSync()
            } label: {
                Text("Sync starten (\(selectedSessionIDs.count) Sessionen)")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSessionIDs.isEmpty)
            .padding()
            .background(.bar)
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            VStack(spacing: 8) {
                phaseText
                    .font(.headline)
                    .multilineTextAlignment(.center)

                phaseDetail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            statsGrid

            if !syncService.errors.isEmpty {
                Text("\(syncService.errors.count) Fehler")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var phaseText: some View {
        switch syncService.phase {
        case .preparingParlamentarier:
            Text("Parlamentarier laden…")
        case .syncingSession(let name, let index, let total):
            Text("Session \(index)/\(total)")
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .syncingGeschaeft(let title, let current, let total):
            Text("Geschäft \(current)/\(total)")
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        case .syncingAbstimmungen(let current, let total):
            Text("Abstimmungen \(current)/\(total)")
            Text("Stimmabgaben laden…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var phaseDetail: some View {
        switch syncService.phase {
        case .syncingGeschaeft(_, let current, let total):
            ProgressView(value: Double(current), total: Double(total))
                .padding(.horizontal)
        case .syncingAbstimmungen(let current, let total):
            ProgressView(value: Double(current), total: Double(total))
                .padding(.horizontal)
        default:
            EmptyView()
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatBox(value: syncService.stats.geschaefteProcessed, label: "Geschäfte")
            StatBox(value: syncService.stats.wortmeldungenCreated, label: "Wortmeldungen")
            StatBox(value: syncService.stats.abstimmungenCreated, label: "Abstimmungen")
            StatBox(value: syncService.stats.stimmabgabenCreated, label: "Stimmabgaben")
        }
        .padding(.top)
    }

    // MARK: - Result

    private var resultView: some View {
        List {
            Section {
                if syncService.phase == .cancelled {
                    Label("Abgebrochen", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                } else {
                    Label("Abgeschlossen", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            Section("Zusammenfassung") {
                if syncService.stats.isIncremental {
                    Label("Inkrementelle Synchronisation", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                LabeledContent("Sessionen", value: "\(syncService.stats.sessionsProcessed)")
                LabeledContent("Geschäfte verarbeitet", value: "\(syncService.stats.geschaefteProcessed)")
                if syncService.stats.geschaefteUpdated > 0 {
                    LabeledContent("Geschäfte aktualisiert", value: "\(syncService.stats.geschaefteUpdated)")
                }
                if syncService.stats.geschaefteSkipped > 0 {
                    LabeledContent("Geschäfte übersprungen", value: "\(syncService.stats.geschaefteSkipped)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Wortmeldungen", value: "\(syncService.stats.wortmeldungenCreated)")
                LabeledContent("Abstimmungen", value: "\(syncService.stats.abstimmungenCreated)")
                LabeledContent("Stimmabgaben", value: "\(syncService.stats.stimmabgabenCreated)")
                if syncService.stats.errorsEncountered > 0 {
                    LabeledContent("Fehler", value: "\(syncService.stats.errorsEncountered)")
                        .foregroundStyle(.red)
                }
            }

            if !syncService.errors.isEmpty {
                Section("Fehler") {
                    ForEach(syncService.errors) { error in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.geschaeftTitle)
                                .font(.caption)
                                .lineLimit(1)
                            Text(error.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Fertig")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ id: Int) {
        if selectedSessionIDs.contains(id) {
            selectedSessionIDs.remove(id)
        } else {
            selectedSessionIDs.insert(id)
        }
    }

    private func startSync() {
        let selected = sessions.filter { selectedSessionIDs.contains($0.id) }
        syncTask = Task {
            await syncService.syncSessions(selected, modelContext: modelContext)
        }
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
