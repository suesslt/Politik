import SwiftUI

// MARK: - Bipolar Bar (-1 to +1)

struct AnalysisBarView: View {
    let label: String
    let value: Double?
    let leftLabel: String
    let rightLabel: String

    var body: some View {
        if let value {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%+.2f", value))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(value < -0.1 ? .red : value > 0.1 ? .blue : .secondary)
                }
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let center = width / 2
                    let normalized = (value + 1) / 2 // map -1...+1 to 0...1
                    let xPos = width * CGFloat(normalized)

                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)

                        // Center line
                        Rectangle()
                            .fill(.secondary.opacity(0.4))
                            .frame(width: 1)
                            .position(x: center, y: geometry.size.height / 2)

                        // Value bar from center
                        let barStart = min(center, xPos)
                        let barWidth = abs(xPos - center)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(value < 0 ? .red.opacity(0.6) : .blue.opacity(0.6))
                            .frame(width: barWidth, height: geometry.size.height - 4)
                            .offset(x: barStart, y: 2)

                        // Dot indicator
                        Circle()
                            .fill(value < 0 ? .red : .blue)
                            .frame(width: 10, height: 10)
                            .position(x: xPos, y: geometry.size.height / 2)
                    }
                }
                .frame(height: 14)

                HStack {
                    Text(leftLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(rightLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Factor Bar (0 to 1)

struct AnalysisFactorView: View {
    let label: String
    let value: Double?

    var body: some View {
        if let value {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", value * 100))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(factorColor(value))
                }
                ProgressView(value: value, total: 1.0)
                    .tint(factorColor(value))
            }
            .padding(.vertical, 2)
        }
    }

    private func factorColor(_ v: Double) -> Color {
        if v < 0.3 { return .red }
        if v < 0.6 { return .orange }
        return .green
    }
}

// MARK: - Complete Analysis Section

struct AnalysisResultSection: View {
    let linksRechts: Double?
    let konservativLiberal: Double?
    let liberaleWirtschaft: Double?
    let innovativerStandort: Double?
    let unabhaengigeStromversorgung: Double?
    let staerkeResilienz: Double?
    let schlankerStaat: Double?

    var body: some View {
        Section {
            AnalysisBarView(label: "Links / Rechts", value: linksRechts,
                           leftLabel: "Links", rightLabel: "Rechts")
            AnalysisBarView(label: "Konservativ / Liberal", value: konservativLiberal,
                           leftLabel: "Konservativ", rightLabel: "Liberal")
            AnalysisFactorView(label: "Liberale Wirtschaft", value: liberaleWirtschaft)
            AnalysisFactorView(label: "Innovativer Standort", value: innovativerStandort)
            AnalysisFactorView(label: "Unabh. Stromversorgung", value: unabhaengigeStromversorgung)
            AnalysisFactorView(label: "Stärke / Resilienz", value: staerkeResilienz)
            AnalysisFactorView(label: "Schlanker Staat", value: schlankerStaat)
        } header: {
            Label("KI-Analyse", systemImage: "brain")
        }
    }
}
