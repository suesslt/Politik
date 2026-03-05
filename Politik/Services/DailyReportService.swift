import Foundation
import SwiftData

@MainActor @Observable
final class DailyReportService {

    enum Phase: Equatable {
        case idle
        case syncing
        case fetchingAgenda
        case generating
        case completed
        case error(message: String)
    }

    private(set) var phase: Phase = .idle

    private let syncService = SessionSyncService()
    private let claudeService = ClaudeService()
    private let parlamentService = ParlamentService()

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

        // Phase 2: Fetch agenda for the specific day via Meeting → Subject → SubjectBusiness
        phase = .fetchingAgenda
        let agendaGeschaefte = try await fetchAgendaGeschaefte(
            session: session,
            reportDate: reportDate,
            modelContext: modelContext
        )

        // Use agenda-based Geschaefte if available, otherwise fall back to all session Geschaefte
        let geschaefte = agendaGeschaefte.isEmpty ? session.geschaefte : agendaGeschaefte

        // Phase 2b: Sync transcripts/Urheber for agenda Geschaefte that lack data
        let geschaefteNeedingSync = geschaefte.filter { g in
            !g.wortmeldungen.contains(where: \.isRede)
        }
        if !geschaefteNeedingSync.isEmpty {
            phase = .syncing
            syncService.reset()
            await syncService.syncGeschaefteDetails(geschaefteNeedingSync, modelContext: modelContext)
        }

        // Phase 3: Generate report via Claude
        phase = .generating
        claudeService.reset()

        let content = try await claudeService.generateDailyReport(
            session: session,
            reportDate: reportDate,
            geschaefte: geschaefte,
            modelContext: modelContext
        )

        // Phase 4: Save or replace existing report for this day
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

    // MARK: - Agenda Fetching (Meeting → Subject → SubjectBusiness)

    private func fetchAgendaGeschaefte(
        session: Session,
        reportDate: Date,
        modelContext: ModelContext
    ) async throws -> [Geschaeft] {
        // Step 1: Fetch all meetings for this session
        let meetings = try await parlamentService.fetchMeetings(sessionID: session.id)

        // Step 2: Find meetings matching the report date
        let calendar = Calendar.current
        let dayMeetings = meetings.filter { meeting in
            guard let dateString = meeting.Date,
                  let meetingDate = ODataDateParser.parse(dateString) else { return false }
            return calendar.isDate(meetingDate, inSameDayAs: reportDate)
        }

        guard !dayMeetings.isEmpty else { return [] }

        // Step 3: For each meeting, fetch subjects → SubjectBusiness → BusinessNumbers
        var businessNumbers = Set<Int>()

        for meeting in dayMeetings {
            guard let meetingID = meeting.ID else { continue }
            let subjects = try await parlamentService.fetchSubjectsForMeeting(meetingID: meetingID)

            for subject in subjects {
                guard let subjectID = subject.ID else { continue }
                let subjectBusinesses = try await parlamentService.fetchSubjectBusinessesForSubject(subjectID: subjectID)
                for sb in subjectBusinesses {
                    if let bn = sb.BusinessNumber {
                        businessNumbers.insert(bn)
                    }
                }
            }
        }

        guard !businessNumbers.isEmpty else { return [] }

        // Step 4: Find existing Geschaefte or fetch missing ones
        let existingLookup = Dictionary(uniqueKeysWithValues: session.geschaefte.map { ($0.id, $0) })
        var result: [Geschaeft] = []

        let missingIDs = businessNumbers.subtracting(existingLookup.keys)

        // Fetch missing Geschaefte from API
        for businessID in missingIDs {
            do {
                if let dto = try await parlamentService.fetchBusiness(id: businessID) {
                    let geschaeft = Geschaeft(
                        id: dto.ID,
                        businessShortNumber: dto.BusinessShortNumber ?? "",
                        title: dto.Title ?? "",
                        businessTypeName: dto.BusinessTypeName ?? "",
                        businessTypeAbbreviation: dto.BusinessTypeAbbreviation ?? "",
                        businessStatusText: dto.BusinessStatusText ?? "",
                        businessStatusDate: ODataDateParser.parse(dto.BusinessStatusDate),
                        submissionDate: ODataDateParser.parse(dto.SubmissionDate),
                        submittedBy: dto.SubmittedBy,
                        descriptionText: dto.Description,
                        submissionCouncilName: dto.SubmissionCouncilName,
                        responsibleDepartmentName: dto.ResponsibleDepartmentName,
                        responsibleDepartmentAbbreviation: dto.ResponsibleDepartmentAbbreviation,
                        tagNames: dto.TagNames,
                        session: session
                    )
                    modelContext.insert(geschaeft)
                    result.append(geschaeft)
                }
            } catch {
                // Skip missing business, continue with others
            }
        }

        if !missingIDs.isEmpty {
            try modelContext.save()
        }

        // Add existing Geschaefte that are on today's agenda
        for bn in businessNumbers {
            if let existing = existingLookup[bn] {
                result.append(existing)
            }
        }

        return result
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
