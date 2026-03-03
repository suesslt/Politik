import SwiftUI
import SwiftData

struct WortmeldungDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let wortmeldung: Wortmeldung

    @State private var claudeService = ClaudeService()
    @State private var isExtracting = false
    @State private var errorMessage: String?

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "de_CH")
        return formatter
    }

    var body: some View {
        List {
            headerSection
            textSection
            propositionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Wortmeldung")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Geschaeft.self) { geschaeft in
            GeschaeftDetailView(geschaeft: geschaeft)
        }
        .navigationDestination(for: Parlamentarier.self) { parlamentarier in
            ParlamentarierDetailView(parlamentarier: parlamentarier)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isExtracting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await extractPropositions() }
                    } label: {
                        Label("Kernaussagen extrahieren", systemImage: "lightbulb")
                    }
                    .disabled(wortmeldung.plainText.isEmpty)
                }
            }
        }
        .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Extraction

    private func extractPropositions() async {
        isExtracting = true
        claudeService.reset()
        do {
            try await claudeService.extractPropositionsFromWortmeldung(
                wortmeldung: wortmeldung,
                modelContext: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isExtracting = false
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // Speaker
                HStack {
                    if let parlamentarier = wortmeldung.parlamentarier {
                        NavigationLink(value: parlamentarier) {
                            speakerLabel
                        }
                    } else {
                        speakerLabel
                    }
                }

                if let function = wortmeldung.speakerFunction, !function.isEmpty {
                    Text(function)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Geschäft
                if let geschaeft = wortmeldung.geschaeft {
                    NavigationLink(value: geschaeft) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Geschäft")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text(geschaeft.businessShortNumber)
                                    .font(.caption.monospaced())
                                Text(geschaeft.businessTypeAbbreviation)
                                    .font(.caption)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(typeColor(geschaeft.businessTypeAbbreviation).opacity(0.15))
                                    .foregroundStyle(typeColor(geschaeft.businessTypeAbbreviation))
                                    .clipShape(Capsule())
                            }
                            Text(geschaeft.title)
                                .font(.subheadline)
                                .lineLimit(3)
                        }
                    }
                }

                // Date
                if let date = wortmeldung.meetingDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatMeetingDate(date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Council
                if let council = wortmeldung.councilName {
                    HStack(spacing: 4) {
                        Image(systemName: "building.columns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(council)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var speakerLabel: some View {
        HStack {
            Text(wortmeldung.speakerFullName)
                .font(.title3.bold())
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
    }

    // MARK: - Text

    private var textSection: some View {
        Section {
            Text(wortmeldung.plainText)
                .font(.body)
                .textSelection(.enabled)
        } header: {
            Label("Rede", systemImage: "text.quote")
        }
    }

    // MARK: - Propositions

    private var propositionsSection: some View {
        Section {
            if wortmeldung.propositions.isEmpty {
                Text("Keine Kernaussagen extrahiert")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let sorted = wortmeldung.propositions.sorted { $0.createdAt < $1.createdAt }
                ForEach(sorted) { proposition in
                    VStack(alignment: .leading, spacing: 6) {
                        // Subject badge
                        Text(proposition.subject)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.teal.opacity(0.12))
                            .foregroundStyle(.teal)
                            .clipShape(Capsule())

                        // Key message
                        Text(proposition.keyMessage)
                            .font(.subheadline)

                        // Date
                        if let date = proposition.dateOfProposition {
                            Text(dateFormatter.string(from: date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Label("Kernaussagen (\(wortmeldung.propositions.count))", systemImage: "lightbulb")
        }
    }

    // MARK: - Helpers

    private func formatMeetingDate(_ dateString: String) -> String {
        guard dateString.count == 8 else { return dateString }
        let day = dateString.suffix(2)
        let month = dateString.dropFirst(4).prefix(2)
        let year = dateString.prefix(4)
        return "\(day).\(month).\(year)"
    }

    private func typeColor(_ abbreviation: String) -> Color {
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
