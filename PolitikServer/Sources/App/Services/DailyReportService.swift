import Foundation
import Vapor
import Fluent

final class DailyReportService: Sendable {
    let parlamentService: ParlamentService
    let claudeService: ClaudeService
    let logger: Logger

    init(parlamentService: ParlamentService, claudeService: ClaudeService, logger: Logger) {
        self.parlamentService = parlamentService
        self.claudeService = claudeService
        self.logger = logger
    }

    struct ReportResult: Content {
        let reportId: UUID
        let content: String
    }

    func generateReport(
        session: Session,
        reportDate: Date,
        on db: Database
    ) async throws -> DailyReport {
        // Phase 1: Sync the session data
        let syncService = SessionSyncService(parlamentService: parlamentService, logger: logger)
        _ = try await syncService.syncSessions([session], on: db)

        // Phase 2: Fetch agenda for specific day
        let agendaGeschaefte = try await fetchAgendaGeschaefte(
            session: session,
            reportDate: reportDate,
            on: db
        )

        // Use agenda or fallback to all session Geschaefte
        try await session.$geschaefte.load(on: db)
        let geschaefte = agendaGeschaefte.isEmpty ? session.geschaefte : agendaGeschaefte

        // Phase 2b: Sync missing transcripts
        let geschaefteNeedingSync = geschaefte.filter { g in
            g.wortmeldungen.isEmpty
        }
        if !geschaefteNeedingSync.isEmpty {
            _ = try await syncService.syncGeschaefteDetails(geschaefteNeedingSync, on: db)
        }

        // Phase 3: Generate report via Claude
        let content = try await claudeService.generateDailyReport(
            session: session,
            reportDate: reportDate,
            geschaefte: geschaefte,
            on: db
        )

        // Phase 4: Save or replace existing report for this day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: reportDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let existing = try await DailyReport.query(on: db)
            .filter(\.$sessionId == session.id!)
            .filter(\.$reportDate >= startOfDay)
            .filter(\.$reportDate < endOfDay)
            .all()

        for old in existing {
            try await old.delete(on: db)
        }

        let report = DailyReport(
            sessionId: session.id!,
            sessionName: session.sessionName,
            reportDate: reportDate,
            content: content
        )
        report.$session.id = session.id
        try await report.save(on: db)

        return report
    }

    // MARK: - Private: Agenda Fetching

    private func fetchAgendaGeschaefte(
        session: Session,
        reportDate: Date,
        on db: Database
    ) async throws -> [Geschaeft] {
        let meetings = try await parlamentService.fetchMeetings(sessionID: session.id!)

        let calendar = Calendar.current
        let dayMeetings = meetings.filter { meeting in
            guard let dateString = meeting.Date,
                  let meetingDate = ODataDateParser.parse(dateString) else { return false }
            return calendar.isDate(meetingDate, inSameDayAs: reportDate)
        }

        guard !dayMeetings.isEmpty else { return [] }

        var businessNumbers = Set<Int>()
        for meeting in dayMeetings {
            guard let meetingID = meeting.ID else { continue }
            let subjects = try await parlamentService.fetchSubjectsForMeeting(meetingID: meetingID)
            for subject in subjects {
                guard let subjectID = subject.ID else { continue }
                let subjectBusinesses = try await parlamentService.fetchSubjectBusinessesForSubject(subjectID: subjectID)
                for sb in subjectBusinesses {
                    if let bn = sb.BusinessNumber { businessNumbers.insert(bn) }
                }
            }
        }

        guard !businessNumbers.isEmpty else { return [] }

        // Find existing Geschaefte
        try await session.$geschaefte.load(on: db)
        let existingLookup = Dictionary(uniqueKeysWithValues: session.geschaefte.compactMap { g -> (Int, Geschaeft)? in
            guard let id = g.id else { return nil }
            return (id, g)
        })

        var result: [Geschaeft] = []
        let missingIDs = businessNumbers.subtracting(existingLookup.keys)

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
                        tagNames: dto.TagNames
                    )
                    geschaeft.$session.id = session.id
                    try await geschaeft.save(on: db)
                    result.append(geschaeft)
                }
            } catch {
                // Skip
            }
        }

        for bn in businessNumbers {
            if let existing = existingLookup[bn] {
                result.append(existing)
            }
        }

        // Load wortmeldungen for each geschaeft
        for geschaeft in result {
            try await geschaeft.$wortmeldungen.load(on: db)
            try await geschaeft.$abstimmungen.load(on: db)
        }

        return result
    }
}
