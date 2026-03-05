import SwiftUI
import SwiftData
import QuickLook

struct DailyReportDetailView: View {
    @Bindable var report: DailyReport
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var editText = ""
    @State private var pdfURL: URL?

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "de_CH")
        return formatter
    }

    var body: some View {
        Group {
            if isEditing {
                editorView
            } else {
                readerView
            }
        }
        .navigationTitle(dateFormatter.string(from: report.reportDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        if isEditing {
                            report.content = editText
                            try? modelContext.save()
                            isEditing = false
                        } else {
                            editText = report.content
                            isEditing = true
                        }
                    } label: {
                        Label(isEditing ? "Speichern" : "Bearbeiten",
                              systemImage: isEditing ? "checkmark" : "pencil")
                    }

                    if !isEditing {
                        Button {
                            exportPDF()
                        } label: {
                            Label("PDF", systemImage: "arrow.down.doc")
                        }
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        isEditing = false
                    }
                }
            }
        }
        .quickLookPreview($pdfURL)
    }

    // MARK: - Reader View (Rendered Markdown)

    private var readerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.sessionName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Erstellt: \(formatCreatedAt(report.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)

                Divider()

                // Markdown content
                Text(markdownAttributedString(from: report.content))
                    .padding(.horizontal)
                    .textSelection(.enabled)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Editor View

    private var editorView: some View {
        TextEditor(text: $editText)
            .font(.system(.body, design: .monospaced))
            .padding(8)
    }

    // MARK: - Markdown Rendering

    private func markdownAttributedString(from markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(markdown)
        }
    }

    private func formatCreatedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_CH")
        return formatter.string(from: date)
    }

    // MARK: - PDF Export

    private func exportPDF() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)) // A4

        let data = renderer.pdfData { context in
            let content = report.content
            let paragraphs = content.components(separatedBy: "\n")

            let pageInset = CGRect(x: 40, y: 40, width: 515, height: 762)
            var currentY: CGFloat = 0

            func beginNewPage() {
                context.beginPage()
                currentY = pageInset.origin.y
            }

            func drawText(_ text: String, font: UIFont, color: UIColor = .black) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let attributedString = NSAttributedString(string: text, attributes: attributes)
                let maxSize = CGSize(width: pageInset.width, height: .greatestFiniteMagnitude)
                let boundingRect = attributedString.boundingRect(with: maxSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

                if currentY + boundingRect.height > pageInset.origin.y + pageInset.height {
                    beginNewPage()
                }

                attributedString.draw(in: CGRect(x: pageInset.origin.x, y: currentY, width: pageInset.width, height: boundingRect.height))
                currentY += boundingRect.height + 4
            }

            beginNewPage()

            for paragraph in paragraphs {
                let trimmed = paragraph.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty {
                    currentY += 8
                    continue
                }

                if trimmed.hasPrefix("# ") {
                    let text = String(trimmed.dropFirst(2))
                    drawText(text, font: .boldSystemFont(ofSize: 20))
                    currentY += 4
                } else if trimmed.hasPrefix("## ") {
                    let text = String(trimmed.dropFirst(3))
                    currentY += 8
                    drawText(text, font: .boldSystemFont(ofSize: 16))
                    currentY += 2
                } else if trimmed.hasPrefix("### ") {
                    let text = String(trimmed.dropFirst(4))
                    currentY += 4
                    drawText(text, font: .boldSystemFont(ofSize: 13))
                } else if trimmed.hasPrefix("- ") {
                    let text = "  \u{2022} " + String(trimmed.dropFirst(2))
                    drawText(text, font: .systemFont(ofSize: 11))
                } else if trimmed.hasPrefix("---") {
                    currentY += 4
                    let lineY = currentY
                    context.cgContext.setStrokeColor(UIColor.gray.cgColor)
                    context.cgContext.setLineWidth(0.5)
                    context.cgContext.move(to: CGPoint(x: pageInset.origin.x, y: lineY))
                    context.cgContext.addLine(to: CGPoint(x: pageInset.origin.x + pageInset.width, y: lineY))
                    context.cgContext.strokePath()
                    currentY += 8
                } else {
                    // Strip bold markers for PDF
                    let cleanText = trimmed
                        .replacingOccurrences(of: "**", with: "")
                        .replacingOccurrences(of: "*", with: "")
                    drawText(cleanText, font: .systemFont(ofSize: 11))
                }
            }
        }

        // Save to temp file and open in Quick Look
        let dateStr = dateFormatter.string(from: report.reportDate)
        let safeDateStr = dateStr
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "")
        let fileName = "Parlamentsbericht_\(safeDateStr).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL)
            pdfURL = tempURL
        } catch {
            // PDF export failed silently
        }
    }
}
