import SwiftUI
import SwiftData
import Charts

struct ParlamentarierChartView: View {
    @Query(sort: \Parlamentarier.lastName) private var allParlamentarier: [Parlamentarier]
    @State private var selectedPerson: Parlamentarier?

    private var analyzed: [Parlamentarier] {
        allParlamentarier.filter { $0.hasAnalysis }
    }

    private var partyGroups: [String] {
        let groups = Set(analyzed.compactMap { $0.parlGroupAbbreviation })
        return groups.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            if analyzed.isEmpty {
                ContentUnavailableView(
                    "Keine Analyse-Daten",
                    systemImage: "chart.dots.scatter",
                    description: Text("Parlamentarier müssen zuerst analysiert werden. Verwende den Brain-Button auf einem Parlamentarier oder die Session-Analyse.")
                )
            } else {
                chartView
                    .padding()

                if let person = selectedPerson {
                    selectedPersonCard(person)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                legendView
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Politische Landschaft")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .status) {
                Text("\(analyzed.count) Parlamentarier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPerson?.personNumber)
    }

    // MARK: - Chart

    private var chartView: some View {
        Chart {
            // Quadrant dividers
            RuleMark(x: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

            // Data points
            ForEach(analyzed, id: \.personNumber) { person in
                PointMark(
                    x: .value("Links-Rechts", person.linksRechts ?? 0),
                    y: .value("Konservativ-Liberal", person.konservativLiberal ?? 0)
                )
                .foregroundStyle(chartColor(for: person.parlGroupAbbreviation))
                .symbolSize(selectedPerson?.personNumber == person.personNumber ? 250 : 60)
                .opacity(selectedPerson == nil || selectedPerson?.personNumber == person.personNumber ? 1.0 : 0.3)
            }

            // Selected person annotation
            if let person = selectedPerson,
               let lr = person.linksRechts,
               let kl = person.konservativLiberal {
                PointMark(
                    x: .value("Links-Rechts", lr),
                    y: .value("Konservativ-Liberal", kl)
                )
                .foregroundStyle(chartColor(for: person.parlGroupAbbreviation))
                .symbolSize(250)
                .annotation(position: annotationPosition(lr: lr, kl: kl), spacing: 6) {
                    Text(person.fullName)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .chartXScale(domain: -1.15...1.15)
        .chartYScale(domain: -1.15...1.15)
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            HStack {
                Text("Links")
                    .foregroundStyle(.red)
                Spacer()
                Text("Rechts")
                    .foregroundStyle(.blue)
            }
            .font(.caption.bold())
            .padding(.horizontal, 4)
        }
        .chartYAxisLabel(position: .trailing, alignment: .center) {
            VStack {
                Text("Liberal")
                    .foregroundStyle(.purple)
                Spacer()
                Text("Konservativ")
                    .foregroundStyle(.brown)
            }
            .font(.caption.bold())
            .padding(.vertical, 4)
        }
        .chartXAxis {
            AxisMarks(values: [-1, -0.5, 0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.1f", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [-1, -0.5, 0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.1f", v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        findNearestPerson(at: location, proxy: proxy, geometry: geometry)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                findNearestPerson(at: drag.location, proxy: proxy, geometry: geometry)
                            }
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Selected Person Card

    private func selectedPersonCard(_ person: Parlamentarier) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(person.fullName)
                    .font(.headline)
                HStack(spacing: 6) {
                    if let party = person.partyAbbreviation {
                        Text(party)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(chartColor(for: person.parlGroupAbbreviation).opacity(0.15))
                            .foregroundStyle(chartColor(for: person.parlGroupAbbreviation))
                            .clipShape(Capsule())
                    }
                    if let canton = person.cantonAbbreviation {
                        Text(canton)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let council = person.councilAbbreviation {
                        Text(council)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("L/R:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.2f", person.linksRechts ?? 0))
                        .font(.caption.bold().monospacedDigit())
                }
                HStack(spacing: 4) {
                    Text("K/L:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.2f", person.konservativLiberal ?? 0))
                        .font(.caption.bold().monospacedDigit())
                }
            }
            Button {
                selectedPerson = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Legend

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(partyGroups, id: \.self) { group in
                    let count = analyzed.filter { $0.parlGroupAbbreviation == group }.count
                    HStack(spacing: 4) {
                        Circle()
                            .fill(chartColor(for: group))
                            .frame(width: 8, height: 8)
                        Text("\(parlGroupDisplayName(group)) (\(count))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    private func findNearestPerson(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        let adjustedLocation = CGPoint(
            x: location.x - origin.x,
            y: location.y - origin.y
        )

        guard let xValue: Double = proxy.value(atX: adjustedLocation.x),
              let yValue: Double = proxy.value(atY: adjustedLocation.y) else { return }

        var nearest: Parlamentarier?
        var minDistance = Double.infinity

        for person in analyzed {
            guard let lr = person.linksRechts,
                  let kl = person.konservativLiberal else { continue }
            let dist = sqrt(pow(lr - xValue, 2) + pow(kl - yValue, 2))
            if dist < minDistance {
                minDistance = dist
                nearest = person
            }
        }

        if minDistance < 0.2 {
            selectedPerson = nearest
        } else {
            selectedPerson = nil
        }
    }

    private func annotationPosition(lr: Double, kl: Double) -> AnnotationPosition {
        // Place annotation away from edges
        if kl > 0.3 { return .bottom }
        if kl < -0.3 { return .top }
        if lr > 0.3 { return .leading }
        if lr < -0.3 { return .trailing }
        return .top
    }

    private func chartColor(for groupAbbreviation: String?) -> Color {
        switch groupAbbreviation {
        case "S": return .red                // SP
        case "G": return Color(.systemGreen) // Grüne
        case "GL": return .teal              // GLP
        case "V": return Color(red: 0.0, green: 0.5, blue: 0.0) // SVP (dark green)
        case "RL", "FDP": return .blue       // FDP
        case "M-E", "M": return .orange      // Die Mitte
        case "BD": return .yellow            // BDP
        default: return .gray
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
