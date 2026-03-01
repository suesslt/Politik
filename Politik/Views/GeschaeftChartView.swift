import SwiftUI
import SwiftData
import Charts

struct GeschaeftChartView: View {
    let session: Session
    @State private var selectedGeschaeft: Geschaeft?

    private var analyzed: [Geschaeft] {
        session.geschaefte.filter { $0.hasAnalysis }
    }

    private var typeGroups: [String] {
        let types = Set(analyzed.map { $0.businessTypeAbbreviation })
        return types.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            if analyzed.isEmpty {
                ContentUnavailableView(
                    "Keine Analyse-Daten",
                    systemImage: "chart.dots.scatter",
                    description: Text("Geschäfte müssen zuerst analysiert werden. Verwende den Brain-Button in der Geschäftsliste.")
                )
            } else {
                chartView
                    .padding()

                if let geschaeft = selectedGeschaeft {
                    selectedGeschaeftCard(geschaeft)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                legendView
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Geschäfte-Landschaft")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .status) {
                Text("\(analyzed.count) von \(session.geschaefte.count) analysiert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedGeschaeft?.id)
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
            ForEach(analyzed, id: \.id) { geschaeft in
                PointMark(
                    x: .value("Links-Rechts", geschaeft.linksRechts ?? 0),
                    y: .value("Konservativ-Liberal", geschaeft.konservativLiberal ?? 0)
                )
                .foregroundStyle(typeColor(for: geschaeft.businessTypeAbbreviation))
                .symbolSize(selectedGeschaeft?.id == geschaeft.id ? 250 : 60)
                .opacity(selectedGeschaeft == nil || selectedGeschaeft?.id == geschaeft.id ? 1.0 : 0.3)
            }

            // Selected annotation
            if let geschaeft = selectedGeschaeft,
               let lr = geschaeft.linksRechts,
               let kl = geschaeft.konservativLiberal {
                PointMark(
                    x: .value("Links-Rechts", lr),
                    y: .value("Konservativ-Liberal", kl)
                )
                .foregroundStyle(typeColor(for: geschaeft.businessTypeAbbreviation))
                .symbolSize(250)
                .annotation(position: annotationPosition(lr: lr, kl: kl), spacing: 6) {
                    Text(geschaeft.businessShortNumber)
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
                        findNearestGeschaeft(at: location, proxy: proxy, geometry: geometry)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                findNearestGeschaeft(at: drag.location, proxy: proxy, geometry: geometry)
                            }
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Selected Geschaeft Card

    private func selectedGeschaeftCard(_ geschaeft: Geschaeft) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(geschaeft.businessShortNumber)
                        .font(.caption.bold().monospaced())
                    Text(geschaeft.businessTypeAbbreviation)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(typeColor(for: geschaeft.businessTypeAbbreviation).opacity(0.15))
                        .foregroundStyle(typeColor(for: geschaeft.businessTypeAbbreviation))
                        .clipShape(Capsule())
                }
                Text(geschaeft.title)
                    .font(.caption)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("L/R:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.2f", geschaeft.linksRechts ?? 0))
                        .font(.caption.bold().monospacedDigit())
                }
                HStack(spacing: 4) {
                    Text("K/L:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.2f", geschaeft.konservativLiberal ?? 0))
                        .font(.caption.bold().monospacedDigit())
                }
            }
            Button {
                selectedGeschaeft = nil
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
                ForEach(typeGroups, id: \.self) { type in
                    let count = analyzed.filter { $0.businessTypeAbbreviation == type }.count
                    HStack(spacing: 4) {
                        Circle()
                            .fill(typeColor(for: type))
                            .frame(width: 8, height: 8)
                        Text("\(typeDisplayName(type)) (\(count))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    private func findNearestGeschaeft(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        let adjustedLocation = CGPoint(
            x: location.x - origin.x,
            y: location.y - origin.y
        )

        guard let xValue: Double = proxy.value(atX: adjustedLocation.x),
              let yValue: Double = proxy.value(atY: adjustedLocation.y) else { return }

        var nearest: Geschaeft?
        var minDistance = Double.infinity

        for geschaeft in analyzed {
            guard let lr = geschaeft.linksRechts,
                  let kl = geschaeft.konservativLiberal else { continue }
            let dist = sqrt(pow(lr - xValue, 2) + pow(kl - yValue, 2))
            if dist < minDistance {
                minDistance = dist
                nearest = geschaeft
            }
        }

        if minDistance < 0.2 {
            selectedGeschaeft = nearest
        } else {
            selectedGeschaeft = nil
        }
    }

    private func annotationPosition(lr: Double, kl: Double) -> AnnotationPosition {
        if kl > 0.3 { return .bottom }
        if kl < -0.3 { return .top }
        if lr > 0.3 { return .leading }
        if lr < -0.3 { return .trailing }
        return .top
    }

    private func typeColor(for abbreviation: String) -> Color {
        switch abbreviation {
        case "BRG": return .purple
        case "Mo.": return .blue
        case "Po.": return .teal
        case "Pa.Iv.": return .orange
        case "Kt.Iv.": return .red
        case "Ip.": return .green
        case "Fra.": return .gray
        case "Emp.": return .indigo
        case "Sta.Iv.": return .pink
        default: return .secondary
        }
    }

    private func typeDisplayName(_ abbreviation: String) -> String {
        switch abbreviation {
        case "BRG": return "Bundesratsgeschäft"
        case "Mo.": return "Motion"
        case "Po.": return "Postulat"
        case "Pa.Iv.": return "Parl. Initiative"
        case "Kt.Iv.": return "Kant. Initiative"
        case "Ip.": return "Interpellation"
        case "Fra.": return "Fragestunde"
        case "Emp.": return "Empfehlung"
        case "Sta.Iv.": return "Standesinitiative"
        default: return abbreviation
        }
    }
}
