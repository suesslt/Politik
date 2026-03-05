import Foundation
import SwiftData

@MainActor @Observable
final class DailyReportService {

    enum Phase: Equatable {
        case idle
        case syncing
        case generating
        case completed
        case error(message: String)
    }

    private(set) var phase: Phase = .idle

    private let syncService = SessionSyncService()
    private let claudeService = ClaudeService()

    var syncPhase: SessionSyncService.SyncPhase { syncService.phase }
    var claudePhase: ClaudeService.AnalysisPhase { claudeService.phase }

    func generateReport(
        session: Session,
        reportDate: Date,
        modelContext: ModelContext
    ) async throws -> DailyReport {
        phase = .syncing

        // Phase 1: Sync the session data from API
        syncService.reset()
        await syncService.syncSessions([session], modelContext: modelContext)

        guard syncService.phase == .completed else {
            let msg = "Synchronisation fehlgeschlagen"
            phase = .error(message: msg)
            throw DailyReportError.syncFailed(msg)
        }

        // Phase 2: Generate report via Claude
        phase = .generating
        claudeService.reset()

        let geschaefte = session.geschaefte
        let content = try await claudeService.generateDailyReport(
            session: session,
            reportDate: reportDate,
            geschaefte: geschaefte,
            modelContext: modelContext
        )

        // Phase 3: Save or replace existing report for this day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: reportDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let sessionId = session.id
        let descriptor = FetchDescriptor<DailyReport>(
            predicate: #Predicate<DailyReport> { report in
                report.sessionId == sessionId &&
                report.reportDate >= startOfDay &&
                report.reportDate < endOfDay
            }
        )
        let existing = try modelContext.fetch(descriptor)
        for old in existing {
            modelContext.delete(old)
        }

        let report = DailyReport(
            sessionId: session.id,
            sessionName: session.sessionName,
            reportDate: reportDate,
            content: content,
            session: session
        )
        modelContext.insert(report)
        try modelContext.save()

        phase = .completed
        return report
    }

    func reset() {
        phase = .idle
        syncService.reset()
        claudeService.reset()
    }
}

enum DailyReportError: LocalizedError {
    case syncFailed(String)
    case noSession

    var errorDescription: String? {
        switch self {
        case .syncFailed(let msg): return msg
        case .noSession: return "Keine Session ausgewählt"
        }
    }
}
