import SwiftUI
import SwiftData

struct SessionAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var claudeService = ClaudeService()
    @State private var analysisTask: Task<Void, Never>?

    let session: Session

    private var unanalyzedCount: Int {
        session.geschaefte.filter { !$0.hasAnalysis }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                switch claudeService.phase {
                case .idle:
                    startView
                case .analyzing:
                    progressView
                case .completed, .error:
                    resultView
                }
            }
            .navigationTitle("KI-Analyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .analyzing = claudeService.phase {
                        Button("Abbrechen") {
                            analysisTask?.cancel()
                        }
                        .foregroundStyle(.red)
                    } else {
                        Button("Schliessen") {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isAnalyzing)
        }
    }

    private var isAnalyzing: Bool {
        if case .analyzing = claudeService.phase { return true }
        return false
    }

    // MARK: - Start

    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            VStack(spacing: 8) {
                Text("Session analysieren")
                    .font(.title3.bold())
                Text(session.sessionName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("\(session.geschaefte.count) Geschäfte total")
                    .font(.subheadline)
                Text("\(unanalyzedCount) noch nicht analysiert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if unanalyzedCount == 0 {
                Label("Alle Geschäfte sind bereits analysiert", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            Button {
                startAnalysis()
            } label: {
                Text("Analyse starten (\(unanalyzedCount) Geschäfte)")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(unanalyzedCount == 0)
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

            if case .analyzing(let current, let total, let title) = claudeService.phase {
                VStack(spacing: 8) {
                    Text("Geschäft \(current) von \(total)")
                        .font(.headline)
                    Text(title)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    ProgressView(value: Double(current), total: Double(total))
                        .padding(.horizontal)
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Result

    private var resultView: some View {
        VStack(spacing: 24) {
            Spacer()

            switch claudeService.phase {
            case .completed(let success, let errors):
                Image(systemName: errors == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(errors == 0 ? .green : .orange)

                VStack(spacing: 8) {
                    Text("Analyse abgeschlossen")
                        .font(.title3.bold())

                    HStack(spacing: 20) {
                        VStack {
                            Text("\(success)")
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(.green)
                            Text("Erfolge")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if errors > 0 {
                            VStack {
                                Text("\(errors)")
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(.red)
                                Text("Fehler")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

            case .error(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            default:
                EmptyView()
            }

            Spacer()
        }
        .padding()
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

    private func startAnalysis() {
        analysisTask = Task {
            await claudeService.analyzeSession(session, modelContext: modelContext)
        }
    }
}
