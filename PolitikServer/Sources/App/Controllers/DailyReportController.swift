import Vapor
import Fluent

struct DailyReportController {
    // MARK: - Web Routes

    func index(req: Request) async throws -> View {
        let reports = try await DailyReport.query(on: req.db)
            .sort(\.$reportDate, .descending)
            .all()

        let sessions = try await Session.query(on: req.db)
            .sort(\.$startDate, .descending)
            .all()

        struct Context: Encodable {
            let title: String
            let reports: [DailyReport]
            let sessions: [Session]
            let currentUser: UserContext?
        }
        return try await req.view.render("reports/index", Context(
            title: "Tagesberichte",
            reports: reports,
            sessions: sessions,
            currentUser: req.userContext
        ))
    }

    func show(req: Request) async throws -> View {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard let report = try await DailyReport.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        struct Context: Encodable {
            let title: String
            let report: DailyReport
            let currentUser: UserContext?
        }
        return try await req.view.render("reports/show", Context(
            title: "Bericht \(report.sessionName)",
            report: report,
            currentUser: req.userContext
        ))
    }

    func generate(req: Request) async throws -> Response {
        struct GenerateRequest: Content {
            let sessionId: Int
            let date: String // yyyy-MM-dd
        }

        let input = try req.content.decode(GenerateRequest.self)

        guard let session = try await Session.find(input.sessionId, on: req.db) else {
            throw Abort(.notFound, reason: "Session nicht gefunden")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let reportDate = formatter.date(from: input.date) else {
            throw Abort(.badRequest, reason: "Ungültiges Datum")
        }

        let reportService = DailyReportService(
            parlamentService: req.parlamentService,
            claudeService: req.claudeService,
            logger: req.logger
        )

        let report = try await reportService.generateReport(
            session: session,
            reportDate: reportDate,
            on: req.db
        )

        return req.redirect(to: "/reports/\(report.id!)")
    }

    // MARK: - API Routes

    func apiIndex(req: Request) async throws -> [DailyReport] {
        try await DailyReport.query(on: req.db)
            .sort(\.$reportDate, .descending)
            .all()
    }

    func apiShow(req: Request) async throws -> DailyReport {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard let report = try await DailyReport.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return report
    }
}
