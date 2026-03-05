import Vapor
import Fluent

struct ParlamentarierController {
    // MARK: - Web Routes

    func index(req: Request) async throws -> View {
        let query = req.query[String.self, at: "q"]
        let faction = req.query[String.self, at: "faction"]
        let canton = req.query[String.self, at: "canton"]
        let council = req.query[String.self, at: "council"]
        let sort = req.query[String.self, at: "sort"] ?? "name"

        var dbQuery = Parlamentarier.query(on: req.db)
            .filter(\.$isActive == true)

        if let query, !query.isEmpty {
            dbQuery = dbQuery.group(.or) { group in
                group.filter(\.$firstName, .custom("ILIKE"), "%\(query)%")
                group.filter(\.$lastName, .custom("ILIKE"), "%\(query)%")
            }
        }
        if let faction, !faction.isEmpty {
            dbQuery = dbQuery.filter(\.$parlGroupAbbreviation == faction)
        }
        if let canton, !canton.isEmpty {
            dbQuery = dbQuery.filter(\.$cantonAbbreviation == canton)
        }
        if let council, !council.isEmpty {
            dbQuery = dbQuery.filter(\.$councilName == council)
        }

        switch sort {
        case "party": dbQuery = dbQuery.sort(\.$partyAbbreviation)
        case "canton": dbQuery = dbQuery.sort(\.$cantonAbbreviation)
        case "faction": dbQuery = dbQuery.sort(\.$parlGroupAbbreviation)
        default: dbQuery = dbQuery.sort(\.$lastName).sort(\.$firstName)
        }

        let parlamentarier = try await dbQuery.all()

        // Get unique values for filters
        let allFactions = Set(parlamentarier.compactMap(\.parlGroupAbbreviation)).sorted()
        let allCantons = Set(parlamentarier.compactMap(\.cantonAbbreviation)).sorted()

        struct Context: Encodable {
            let title: String
            let parlamentarier: [Parlamentarier]
            let query: String?
            let faction: String?
            let canton: String?
            let council: String?
            let sort: String
            let factions: [String]
            let cantons: [String]
        }
        return try await req.view.render("parlamentarier/index", Context(
            title: "Parlamentarier",
            parlamentarier: parlamentarier,
            query: query,
            faction: faction,
            canton: canton,
            council: council,
            sort: sort,
            factions: allFactions,
            cantons: allCantons
        ))
    }

    func show(req: Request) async throws -> View {
        guard let pn = req.parameters.get("personNumber", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let person = try await Parlamentarier.find(pn, on: req.db) else {
            throw Abort(.notFound)
        }

        try await person.$occupations.load(on: req.db)
        try await person.$interests.load(on: req.db)
        try await person.$wortmeldungen.load(on: req.db)
        try await person.$propositions.load(on: req.db)

        // Load recent votes
        let recentVotes = try await Stimmabgabe.query(on: req.db)
            .filter(\.$parlamentarier.$id == pn)
            .with(\.$abstimmung)
            .sort(\.$id, .descending)
            .limit(30)
            .all()

        struct Context: Encodable {
            let title: String
            let person: Parlamentarier
            let occupations: [PersonOccupation]
            let interests: [PersonInterest]
            let recentVotes: [Stimmabgabe]
            let propositions: [Proposition]
        }
        return try await req.view.render("parlamentarier/show", Context(
            title: person.fullName,
            person: person,
            occupations: person.occupations,
            interests: person.interests,
            recentVotes: recentVotes,
            propositions: person.propositions
        ))
    }

    func analyze(req: Request) async throws -> Response {
        guard let pn = req.parameters.get("personNumber", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let person = try await Parlamentarier.find(pn, on: req.db) else {
            throw Abort(.notFound)
        }

        try await req.claudeService.analyzeParlamentarier(person, on: req.db)
        return req.redirect(to: "/parlamentarier/\(pn)")
    }

    // MARK: - API Routes

    func apiIndex(req: Request) async throws -> [Parlamentarier] {
        try await Parlamentarier.query(on: req.db)
            .filter(\.$isActive == true)
            .sort(\.$lastName)
            .sort(\.$firstName)
            .all()
    }

    func apiShow(req: Request) async throws -> Parlamentarier {
        guard let pn = req.parameters.get("personNumber", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let person = try await Parlamentarier.find(pn, on: req.db) else {
            throw Abort(.notFound)
        }
        return person
    }
}
