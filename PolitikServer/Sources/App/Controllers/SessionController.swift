import Vapor
import Fluent

struct SessionController {
    // MARK: - Web Routes

    func index(req: Request) async throws -> View {
        let sessions = try await Session.query(on: req.db)
            .sort(\.$startDate, .descending)
            .all()

        struct Context: Encodable {
            let title: String
            let sessions: [Session]
        }
        return try await req.view.render("sessions/index", Context(
            title: "Sessions",
            sessions: sessions
        ))
    }

    func show(req: Request) async throws -> View {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let session = try await Session.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        let geschaefte = try await Geschaeft.query(on: req.db)
            .filter(\.$session.$id == id)
            .sort(\.$businessShortNumber)
            .all()

        // Load urheber for each geschaeft
        for geschaeft in geschaefte {
            try await geschaeft.$urheber.load(on: req.db)
        }

        struct Context: Encodable {
            let title: String
            let session: Session
            let geschaefte: [Geschaeft]
        }
        return try await req.view.render("sessions/show", Context(
            title: session.sessionName,
            session: session,
            geschaefte: geschaefte
        ))
    }

    func sync(req: Request) async throws -> Response {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let session = try await Session.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        let syncService = SessionSyncService(
            parlamentService: req.parlamentService,
            logger: req.logger
        )
        let result = try await syncService.syncSessions([session], on: req.db)

        // Redirect back to session with flash message
        let sessionsCount = result.sessionsProcessed
        let geschaefteCount = result.geschaefteProcessed
        req.session.data["flash"] = "Sync abgeschlossen: \(sessionsCount) Sessions, \(geschaefteCount) Geschäfte"

        return req.redirect(to: "/sessions/\(id)")
    }

    // MARK: - API Routes

    func apiIndex(req: Request) async throws -> [Session] {
        try await Session.query(on: req.db)
            .sort(\.$startDate, .descending)
            .all()
    }

    func apiShow(req: Request) async throws -> Session {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let session = try await Session.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return session
    }

    func apiSync(req: Request) async throws -> SessionSyncService.SyncResult {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let session = try await Session.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        let syncService = SessionSyncService(
            parlamentService: req.parlamentService,
            logger: req.logger
        )
        return try await syncService.syncSessions([session], on: req.db)
    }
}
