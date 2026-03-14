import Foundation
import SwiftData

struct CSVExporter {
    static let headers = [
        "PersonNumber",
        "FirstName",
        "LastName",
        "Party",
        "ParlGroup",
        "Canton",
        "Council",
        "Active",
        "LinksRechts",
        "KonservativLiberal",
        "LiberaleWirtschaft",
        "InnovativerStandort",
        "UnabhaengigeStromversorgung",
        "StaerkeResilienz",
        "SchlankerStaat",
    ]

    static func export(parlamentarier: [Parlamentarier]) -> String {
        var lines: [String] = []
        lines.append(headers.joined(separator: ";"))

        let sortedList = parlamentarier.sorted { $0.lastName < $1.lastName }

        for p in sortedList {
            let fields: [String] = [
                String(p.personNumber),
                escapeCSV(p.firstName),
                escapeCSV(p.lastName),
                escapeCSV(p.partyAbbreviation ?? ""),
                escapeCSV(p.parlGroupAbbreviation ?? ""),
                escapeCSV(p.cantonAbbreviation ?? ""),
                escapeCSV(p.councilAbbreviation ?? ""),
                p.isActive ? "1" : "0",
                formatDouble(p.linksRechts),
                formatDouble(p.konservativLiberal),
                formatDouble(p.liberaleWirtschaft),
                formatDouble(p.innovativerStandort),
                formatDouble(p.unabhaengigeStromversorgung),
                formatDouble(p.staerkeResilienz),
                formatDouble(p.schlankerStaat),
            ]
            lines.append(fields.joined(separator: ";"))
        }

        return lines.joined(separator: "\n")
    }

    static func writeToDesktop(content: String) throws -> URL {
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("parlamentarier.csv")

        try content.write(to: desktopURL, atomically: true, encoding: .utf8)
        return desktopURL
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func formatDouble(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }
}
