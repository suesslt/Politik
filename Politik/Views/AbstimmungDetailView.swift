import SwiftUI
import SwiftData

struct AbstimmungDetailView: View {
    let abstimmung: Abstimmung

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_CH")
        return f
    }

    var body: some View {
        List {
            headerSection
            resultSection
            if !fraktionResults.isEmpty {
                fraktionSection
            }
            stimmabgabenSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(abstimmung.businessShortNumber ?? "Abstimmung")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Parlamentarier.self) { parlamentarier in
            ParlamentarierDetailView(parlamentarier: parlamentarier)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            if let subject = abstimmung.subject, !subject.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gegenstand")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(subject)
                        .font(.subheadline)
                }
            }
            if let billTitle = abstimmung.billTitle, !billTitle.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Titel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(billTitle)
                        .font(.subheadline)
                }
            }
            if let bsn = abstimmung.businessShortNumber {
                DetailRow(label: "Geschäftsnummer", value: bsn)
            }
            if let voteEnd = abstimmung.voteEnd {
                DetailRow(label: "Abstimmungszeitpunkt", value: dateFormatter.string(from: voteEnd))
            }
            if let yes = abstimmung.meaningYes, !yes.isEmpty {
                DetailRow(label: "Bedeutung Ja", value: yes)
            }
            if let no = abstimmung.meaningNo, !no.isEmpty {
                DetailRow(label: "Bedeutung Nein", value: no)
            }
        } header: {
            Label("Abstimmung", systemImage: "hand.thumbsup")
        }
    }

    // MARK: - Result

    private var resultSection: some View {
        Section {
            let ja = abstimmung.jaCount
            let nein = abstimmung.neinCount
            let enth = abstimmung.enthaltungCount
            let nichtTeil = abstimmung.nichtTeilgenommenCount
            let entsch = abstimmung.entschuldigtCount
            let total = abstimmung.stimmabgaben.count

            // Result badges
            HStack(spacing: 16) {
                VoteBadge(label: "Ja", value: ja, color: .green)
                VoteBadge(label: "Nein", value: nein, color: .red)
                VoteBadge(label: "Enth.", value: enth, color: .orange)
            }
            .padding(.vertical, 4)

            // Result bar
            if total > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        HStack(spacing: 1) {
                            if ja > 0 {
                                Rectangle()
                                    .fill(.green)
                                    .frame(width: geometry.size.width * CGFloat(ja) / CGFloat(total))
                            }
                            if nein > 0 {
                                Rectangle()
                                    .fill(.red)
                                    .frame(width: geometry.size.width * CGFloat(nein) / CGFloat(total))
                            }
                            if enth > 0 {
                                Rectangle()
                                    .fill(.orange)
                                    .frame(width: geometry.size.width * CGFloat(enth) / CGFloat(total))
                            }
                            let other = nichtTeil + entsch + (total - ja - nein - enth - nichtTeil - entsch)
                            if other > 0 {
                                Rectangle()
                                    .fill(.gray.opacity(0.3))
                                    .frame(width: geometry.size.width * CGFloat(other) / CGFloat(total))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 12)

                    HStack {
                        Text("Total: \(total) Stimmen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if nichtTeil + entsch > 0 {
                            Text("\(nichtTeil) abwesend, \(entsch) entschuldigt")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Outcome
            if ja > nein {
                Label("Angenommen", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.bold())
            } else if nein > ja {
                Label("Abgelehnt", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline.bold())
            } else if ja == nein && total > 0 {
                Label("Stimmengleichheit", systemImage: "equal.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline.bold())
            }
        } header: {
            Label("Ergebnis", systemImage: "chart.bar")
        }
    }

    // MARK: - Fraktion Breakdown

    private struct FraktionResult: Identifiable {
        let id: String  // abbreviation
        let abbreviation: String
        var ja: Int = 0
        var nein: Int = 0
        var enthaltung: Int = 0
        var andere: Int = 0
        var total: Int { ja + nein + enthaltung + andere }
    }

    private var fraktionResults: [FraktionResult] {
        var grouped: [String: FraktionResult] = [:]
        for stimmabgabe in abstimmung.stimmabgaben {
            let group = stimmabgabe.parlamentarier?.parlGroupAbbreviation ?? "?"
            if grouped[group] == nil {
                grouped[group] = FraktionResult(id: group, abbreviation: group)
            }
            switch stimmabgabe.decision {
            case 1: grouped[group]!.ja += 1
            case 2: grouped[group]!.nein += 1
            case 3: grouped[group]!.enthaltung += 1
            default: grouped[group]!.andere += 1
            }
        }
        return grouped.values.sorted { $0.total > $1.total }
    }

    private var fraktionSection: some View {
        Section {
            ForEach(fraktionResults) { result in
                HStack {
                    Text(result.abbreviation)
                        .font(.caption.bold())
                        .frame(width: 40, alignment: .leading)
                        .foregroundStyle(parlGroupColor(result.abbreviation))

                    // Mini bar
                    GeometryReader { geometry in
                        let barWidth = geometry.size.width
                        let total = max(result.total, 1)
                        HStack(spacing: 0) {
                            if result.ja > 0 {
                                Rectangle()
                                    .fill(.green)
                                    .frame(width: barWidth * CGFloat(result.ja) / CGFloat(total))
                            }
                            if result.nein > 0 {
                                Rectangle()
                                    .fill(.red)
                                    .frame(width: barWidth * CGFloat(result.nein) / CGFloat(total))
                            }
                            if result.enthaltung > 0 {
                                Rectangle()
                                    .fill(.orange)
                                    .frame(width: barWidth * CGFloat(result.enthaltung) / CGFloat(total))
                            }
                            if result.andere > 0 {
                                Rectangle()
                                    .fill(.gray.opacity(0.3))
                                    .frame(width: barWidth * CGFloat(result.andere) / CGFloat(total))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .frame(height: 10)

                    HStack(spacing: 8) {
                        Text("\(result.ja)")
                            .foregroundStyle(.green)
                        Text("\(result.nein)")
                            .foregroundStyle(.red)
                        Text("\(result.enthaltung)")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption.monospacedDigit())
                    .frame(width: 80, alignment: .trailing)
                }
            }
        } header: {
            Label("Nach Fraktion", systemImage: "person.3")
        }
    }

    // MARK: - Individual Votes

    private var stimmabgabenSection: some View {
        Section {
            let sorted = abstimmung.stimmabgaben.sorted { a, b in
                if a.decision != b.decision { return a.decision < b.decision }
                return (a.parlamentarier?.lastName ?? "") < (b.parlamentarier?.lastName ?? "")
            }

            ForEach(sorted) { stimmabgabe in
                if let parlamentarier = stimmabgabe.parlamentarier {
                    NavigationLink(value: parlamentarier) {
                        stimmabgabeRow(stimmabgabe)
                    }
                } else {
                    stimmabgabeRow(stimmabgabe)
                }
            }
        } header: {
            Label("Einzelstimmen (\(abstimmung.stimmabgaben.count))", systemImage: "list.bullet")
        }
    }

    private func stimmabgabeRow(_ stimmabgabe: Stimmabgabe) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stimmabgabe.parlamentarier?.fullName ?? "Person \(stimmabgabe.personNumber)")
                    .font(.subheadline)
                HStack(spacing: 6) {
                    if let group = stimmabgabe.parlamentarier?.parlGroupAbbreviation {
                        Text(group)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(parlGroupColor(group).opacity(0.1))
                            .foregroundStyle(parlGroupColor(group))
                            .clipShape(Capsule())
                    }
                    if let canton = stimmabgabe.parlamentarier?.cantonAbbreviation {
                        Text(canton)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(stimmabgabe.decisionDisplayText)
                .font(.caption.bold())
                .foregroundStyle(stimmabgabe.decisionColor)
        }
    }
}
