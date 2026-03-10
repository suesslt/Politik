import Vapor
import Fluent

struct SyncController {
    func index(req: Request) async throws -> View {
        let sessions = try await Session.query(on: req.db)
            .sort(\.$startDate, .descending)
            .all()

        // Count stats
        let geschaefteCount = try await Geschaeft.query(on: req.db).count()
        let parlamentarierCount = try await Parlamentarier.query(on: req.db).count()
        let wortmeldungenCount = try await Wortmeldung.query(on: req.db).count()
        let abstimmungenCount = try await Abstimmung.query(on: req.db).count()

        // Read and consume flash message
        let flash = req.session.data["flash"]
        let flashType = req.session.data["flashType"] ?? "success"
        req.session.data["flash"] = nil
        req.session.data["flashType"] = nil

        struct Context: Encodable {
            let title: String
            let sessions: [Session]
            let geschaefteCount: Int
            let parlamentarierCount: Int
            let wortmeldungenCount: Int
            let abstimmungenCount: Int
            let currentUser: UserContext?
            let flash: String?
            let flashType: String?
        }
        return try await req.view.render("sync/index", Context(
            title: "Synchronisation",
            sessions: sessions,
            geschaefteCount: geschaefteCount,
            parlamentarierCount: parlamentarierCount,
            wortmeldungenCount: wortmeldungenCount,
            abstimmungenCount: abstimmungenCount,
            currentUser: req.userContext,
            flash: flash,
            flashType: flashType
        ))
    }

    func syncSessions(req: Request) async throws -> Response {
        struct SyncRequest: Content {
            let sessionIds: [Int]
        }

        // Decode form data
        let input: SyncRequest
        do {
            input = try req.content.decode(SyncRequest.self)
        } catch {
            req.logger.error("Failed to decode sync request: \(error)")
            req.session.data["flash"] = "Fehler: Keine Sessions ausgewählt."
            req.session.data["flashType"] = "error"
            return req.redirect(to: "/sync")
        }

        req.logger.info("Sync requested for session IDs: \(input.sessionIds)")

        var sessions: [Session] = []
        for id in input.sessionIds {
            if let session = try await Session.find(id, on: req.db) {
                sessions.append(session)
            }
        }

        guard !sessions.isEmpty else {
            req.session.data["flash"] = "Keine gültigen Sessions ausgewählt."
            req.session.data["flashType"] = "error"
            return req.redirect(to: "/sync")
        }

        let syncService = SessionSyncService(
            parlamentService: req.parlamentService,
            logger: req.logger
        )

        do {
            let result = try await syncService.syncSessions(sessions, on: req.db)

            var message = "Sync abgeschlossen: \(result.sessionsProcessed) Sessions, " +
                "\(result.geschaefteProcessed) Geschäfte, " +
                "\(result.wortmeldungenCreated) Wortmeldungen, " +
                "\(result.abstimmungenCreated) Abstimmungen, " +
                "\(result.stimmabgabenCreated) Stimmabgaben"

            if result.errorsEncountered > 0 {
                message += " — \(result.errorsEncountered) Fehler: "
                message += result.errors.prefix(5).joined(separator: "; ")
                if result.errors.count > 5 {
                    message += " (und \(result.errors.count - 5) weitere)"
                }
            }

            req.logger.info("Sync result: \(message)")
            if !result.errors.isEmpty {
                req.logger.warning("Sync errors: \(result.errors)")
            }

            req.session.data["flash"] = message
            req.session.data["flashType"] = result.errorsEncountered > 0 ? "warning" : "success"
        } catch {
            let errorDetail = String(reflecting: error)
            req.logger.error("Sync failed with exception: \(errorDetail)")
            req.session.data["flash"] = "Sync fehlgeschlagen: \(errorDetail)"
            req.session.data["flashType"] = "error"
        }

        return req.redirect(to: "/sync")
    }

    func status(req: Request) async throws -> SyncStatusResponse {
        let geschaefteCount = try await Geschaeft.query(on: req.db).count()
        let parlamentarierCount = try await Parlamentarier.query(on: req.db).count()
        let wortmeldungenCount = try await Wortmeldung.query(on: req.db).count()
        let abstimmungenCount = try await Abstimmung.query(on: req.db).count()
        let stimmabgabenCount = try await Stimmabgabe.query(on: req.db).count()

        return SyncStatusResponse(
            geschaefte: geschaefteCount,
            parlamentarier: parlamentarierCount,
            wortmeldungen: wortmeldungenCount,
            abstimmungen: abstimmungenCount,
            stimmabgaben: stimmabgabenCount
        )
    }

    struct SyncStatusResponse: Content {
        let geschaefte: Int
        let parlamentarier: Int
        let wortmeldungen: Int
        let abstimmungen: Int
        let stimmabgaben: Int
    }

    // MARK: - Load Sessions from API

    func loadSessions(req: Request) async throws -> Response {
        let dtos = try await req.parlamentService.fetchSessions()

        for dto in dtos {
            let existing = try await Session.find(dto.ID, on: req.db)
            if existing != nil { continue }

            let session = Session(
                id: dto.ID,
                sessionNumber: dto.SessionNumber ?? 0,
                sessionName: dto.SessionName ?? "",
                abbreviation: dto.Abbreviation ?? "",
                startDate: ODataDateParser.parse(dto.StartDate),
                endDate: ODataDateParser.parse(dto.EndDate),
                title: dto.Title ?? "",
                type: dto.SessionType ?? 0,
                typeName: dto.TypeName ?? "",
                legislativePeriodNumber: dto.LegislativePeriodNumber ?? 0
            )
            try await session.save(on: req.db)
        }

        return req.redirect(to: "/sessions")
    }
}
