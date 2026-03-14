import SwiftUI
import SwiftData

struct ExportView: View {
    @Query(sort: \Parlamentarier.lastName) private var parlamentarier: [Parlamentarier]
    @State private var exportState: ExportState = .ready

    enum ExportState {
        case ready
        case exporting
        case success(URL, Int)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tablecells")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Parlamentarier CSV Export")
                .font(.title)

            Text("\(parlamentarier.count) Parlamentarier in der Datenbank")
                .foregroundStyle(.secondary)

            switch exportState {
            case .ready:
                Button("CSV exportieren") {
                    exportCSV()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(parlamentarier.isEmpty)

            case .exporting:
                ProgressView("Exportiere...")

            case .success(let url, let count):
                Label("\(count) Parlamentarier exportiert", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)

                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button("Im Finder anzeigen") {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                    Button("Erneut exportieren") {
                        exportCSV()
                    }
                }

            case .error(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)

                Button("Erneut versuchen") {
                    exportCSV()
                }
            }
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            if !parlamentarier.isEmpty {
                exportCSV()
            }
        }
    }

    private func exportCSV() {
        exportState = .exporting
        let csvContent = CSVExporter.export(parlamentarier: parlamentarier)
        do {
            let url = try CSVExporter.writeToDesktop(content: csvContent)
            exportState = .success(url, parlamentarier.count)
        } catch {
            exportState = .error("Export fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
