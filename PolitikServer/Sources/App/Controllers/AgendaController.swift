import Vapor
import Fluent

struct AgendaController {

    // MARK: - Index: Session auswählen, Sitzungstage anzeigen

    func index(req: Request) async throws -> View {
        let sessions = try await Session.query(on: req.db)
            .sort(\.$startDate, .descending)
            .all()

        let selectedSessionId = req.query[Int.self, at: "sessionId"]

        var meetingDays: [MeetingDayView] = []
        var selectedSessionName: String?

        if let sessionId = selectedSessionId,
           let session = sessions.first(where: { $0.id == sessionId }) {
            selectedSessionName = session.sessionName

            let meetings = try await req.parlamentService.fetchMeetings(sessionID: sessionId)

            // Group meetings by date
            var dayMap: [String: [MeetingView]] = [:]
            for meeting in meetings {
                guard let dateString = meeting.Date else { continue }
                let dateKey = String(dateString.prefix(10)) // YYYYMMDD or date portion

                let view = MeetingView(
                    id: meeting.ID ?? "",
                    councilName: meeting.CouncilName ?? "",
                    councilAbbreviation: meeting.CouncilAbbreviation ?? "",
                    meetingOrderText: meeting.MeetingOrderText ?? "",
                    sortOrder: meeting.SortOrder ?? 0
                )

                dayMap[dateKey, default: []].append(view)
            }

            // Sort days descending
            meetingDays = dayMap.map { (dateKey, meetings) in
                MeetingDayView(
                    dateKey: dateKey,
                    displayDate: formatDate(dateKey),
                    meetings: meetings.sorted { $0.sortOrder < $1.sortOrder }
                )
            }.sorted { $0.dateKey > $1.dateKey }
        }

        struct Context: Encodable {
            let title: String
            let sessions: [Session]
            let selectedSessionId: Int?
            let selectedSessionName: String?
            let meetingDays: [MeetingDayView]
            let currentUser: UserContext?
        }

        return try await req.view.render("agenda/index", Context(
            title: "Sitzungsagenden",
            sessions: sessions,
            selectedSessionId: selectedSessionId,
            selectedSessionName: selectedSessionName,
            meetingDays: meetingDays,
            currentUser: req.userContext
        ))
    }

    // MARK: - Day: Tagesordnung eines Sitzungstages

    func day(req: Request) async throws -> View {
        guard let sessionId = req.query[Int.self, at: "sessionId"],
              let dateParam = req.query[String.self, at: "date"] else {
            throw Abort(.badRequest, reason: "sessionId und date Parameter erforderlich")
        }

        guard let session = try await Session.find(sessionId, on: req.db) else {
            throw Abort(.notFound, reason: "Session nicht gefunden")
        }

        // Fetch meetings for the session
        let allMeetings = try await req.parlamentService.fetchMeetings(sessionID: sessionId)

        // Filter meetings for the requested date
        let dayMeetings = allMeetings.filter { meeting in
            guard let dateString = meeting.Date else { return false }
            return dateString.hasPrefix(dateParam)
        }.sorted { ($0.SortOrder ?? 0) < ($1.SortOrder ?? 0) }

        // For each meeting, fetch subjects and their business items
        var agendaBlocks: [AgendaBlockView] = []

        for meeting in dayMeetings {
            guard let meetingID = meeting.ID else { continue }

            let subjects = try await req.parlamentService.fetchSubjectsForMeeting(meetingID: meetingID)
            var businessItems: [AgendaBusinessView] = []

            for subject in subjects.sorted(by: { ($0.SortOrder ?? 0) < ($1.SortOrder ?? 0) }) {
                guard let subjectID = subject.ID else { continue }
                let subjectBusinesses = try await req.parlamentService.fetchSubjectBusinessesForSubject(subjectID: subjectID)

                for sb in subjectBusinesses.sorted(by: { ($0.SortOrder ?? 0) < ($1.SortOrder ?? 0) }) {
                    // Try to find matching Geschaeft in DB for link
                    var geschaeftId: Int? = nil
                    if let bn = sb.BusinessNumber {
                        let existing = try await Geschaeft.find(bn, on: req.db)
                        geschaeftId = existing?.id
                    }

                    businessItems.append(AgendaBusinessView(
                        businessNumber: sb.BusinessNumber,
                        businessShortNumber: sb.BusinessShortNumber ?? "",
                        title: sb.Title ?? "",
                        geschaeftId: geschaeftId
                    ))
                }
            }

            agendaBlocks.append(AgendaBlockView(
                councilName: meeting.CouncilName ?? "",
                councilAbbreviation: meeting.CouncilAbbreviation ?? "",
                meetingOrderText: meeting.MeetingOrderText ?? "",
                businesses: businessItems
            ))
        }

        struct Context: Encodable {
            let title: String
            let session: Session
            let displayDate: String
            let dateParam: String
            let agendaBlocks: [AgendaBlockView]
            let currentUser: UserContext?
        }

        return try await req.view.render("agenda/day", Context(
            title: "Agenda \(formatDate(dateParam))",
            session: session,
            displayDate: formatDate(dateParam),
            dateParam: dateParam,
            agendaBlocks: agendaBlocks,
            currentUser: req.userContext
        ))
    }

    // MARK: - Helper Types

    private func formatDate(_ dateKey: String) -> String {
        // Convert YYYYMMDD or YYYY-MM-DD to DD.MM.YYYY
        let cleaned = dateKey.replacingOccurrences(of: "-", with: "")
        guard cleaned.count >= 8 else { return dateKey }
        let year = cleaned.prefix(4)
        let month = cleaned.dropFirst(4).prefix(2)
        let day = cleaned.dropFirst(6).prefix(2)
        return "\(day).\(month).\(year)"
    }
}

// MARK: - View Models

struct MeetingView: Encodable {
    let id: String
    let councilName: String
    let councilAbbreviation: String
    let meetingOrderText: String
    let sortOrder: Int
}

struct MeetingDayView: Encodable {
    let dateKey: String
    let displayDate: String
    let meetings: [MeetingView]
}

struct AgendaBusinessView: Encodable {
    let businessNumber: Int?
    let businessShortNumber: String
    let title: String
    let geschaeftId: Int?
}

struct AgendaBlockView: Encodable {
    let councilName: String
    let councilAbbreviation: String
    let meetingOrderText: String
    let businesses: [AgendaBusinessView]
}
