import Vapor
import Fluent

struct GeschaeftController {
    // MARK: - Web Routes

    func show(req: Request) async throws -> View {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let geschaeft = try await Geschaeft.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        try await geschaeft.$session.load(on: req.db)
        try await geschaeft.$urheber.load(on: req.db)
        try await geschaeft.$wortmeldungen.load(on: req.db)
        try await geschaeft.$abstimmungen.load(on: req.db)

        // Sort wortmeldungen
        let wortmeldungen = geschaeft.wortmeldungen
            .filter { $0.isRede }
            .sorted { $0.sortOrder < $1.sortOrder }

        // Load stimmabgaben for abstimmungen
        for abstimmung in geschaeft.abstimmungen {
            try await abstimmung.$stimmabgaben.load(on: req.db)
            for stimmabgabe in abstimmung.stimmabgaben {
                try await stimmabgabe.$parlamentarier.load(on: req.db)
            }
        }

        struct Context: Encodable {
            let title: String
            let geschaeft: Geschaeft
            let wortmeldungen: [Wortmeldung]
            let abstimmungen: [Abstimmung]
            let session: Session?
            let urheber: Parlamentarier?
            let linksRechtsPercent: Int
            let konservativLiberalPercent: Int
            let liberaleWirtschaftPercent: Int
            let innovativerStandortPercent: Int
            let stromversorgungPercent: Int
            let currentUser: UserContext?
        }
        return try await req.view.render("geschaefte/show", Context(
            title: geschaeft.businessShortNumber,
            geschaeft: geschaeft,
            wortmeldungen: wortmeldungen,
            abstimmungen: geschaeft.abstimmungen,
            session: geschaeft.session,
            urheber: geschaeft.urheber,
            linksRechtsPercent: Int(((geschaeft.linksRechts ?? 0) + 1) / 2 * 100),
            konservativLiberalPercent: Int(((geschaeft.konservativLiberal ?? 0) + 1) / 2 * 100),
            liberaleWirtschaftPercent: Int((geschaeft.liberaleWirtschaft ?? 0) * 100),
            innovativerStandortPercent: Int((geschaeft.innovativerStandort ?? 0) * 100),
            stromversorgungPercent: Int((geschaeft.unabhaengigeStromversorgung ?? 0) * 100),
            currentUser: req.userContext
        ))
    }

    func analyze(req: Request) async throws -> Response {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let geschaeft = try await Geschaeft.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        try await req.claudeService.analyzeGeschaeft(geschaeft, on: req.db)
        return req.redirect(to: "/geschaefte/\(id)")
    }

    // MARK: - API Routes

    func apiShow(req: Request) async throws -> Geschaeft {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let geschaeft = try await Geschaeft.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return geschaeft
    }

    func apiAnalyze(req: Request) async throws -> AnalysisResult {
        guard let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let geschaeft = try await Geschaeft.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        try await req.claudeService.analyzeGeschaeft(geschaeft, on: req.db)

        return AnalysisResult(
            linksRechts: geschaeft.linksRechts,
            konservativLiberal: geschaeft.konservativLiberal,
            liberaleWirtschaft: geschaeft.liberaleWirtschaft,
            innovativerStandort: geschaeft.innovativerStandort,
            unabhaengigeStromversorgung: geschaeft.unabhaengigeStromversorgung,
            staerkeResilienz: geschaeft.staerkeResilienz,
            schlankerStaat: geschaeft.schlankerStaat
        )
    }
}
