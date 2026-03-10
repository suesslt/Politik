import Vapor
import Fluent

struct WortmeldungController {
    func index(req: Request) async throws -> View {
        let query = req.query[String.self, at: "q"]
        let faction = req.query[String.self, at: "faction"]
        let canton = req.query[String.self, at: "canton"]
        let council = req.query[String.self, at: "council"]
        let page = req.query[Int.self, at: "page"] ?? 1
        let perPage = 50

        var dbQuery = Wortmeldung.query(on: req.db)
            .filter(\.$type == 1)

        if let query, !query.isEmpty {
            dbQuery = dbQuery.group(.or) { group in
                group.filter(\.$text, .custom("ILIKE"), "%\(query)%")
                group.filter(\.$speakerFullName, .custom("ILIKE"), "%\(query)%")
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

        let totalCount = try await dbQuery.count()
        let totalPages = max(1, (totalCount + perPage - 1) / perPage)
        let clampedPage = min(max(page, 1), totalPages)

        let wortmeldungen = try await dbQuery
            .with(\.$geschaeft)
            .sort(\.$meetingDate, .descending)
            .sort(\.$sortOrder)
            .range((clampedPage - 1) * perPage ..< clampedPage * perPage)
            .all()

        // Get unique values for filters
        let allFactions = try await Wortmeldung.query(on: req.db)
            .filter(\.$type == 1)
            .unique()
            .all(\.$parlGroupAbbreviation)
            .compactMap { $0 }
            .sorted()

        let allCantons = try await Wortmeldung.query(on: req.db)
            .filter(\.$type == 1)
            .unique()
            .all(\.$cantonAbbreviation)
            .compactMap { $0 }
            .sorted()

        struct Context: Encodable {
            let title: String
            let wortmeldungen: [WortmeldungView]
            let query: String?
            let faction: String?
            let canton: String?
            let council: String?
            let factions: [String]
            let cantons: [String]
            let totalCount: Int
            let page: Int
            let totalPages: Int
            let currentUser: UserContext?
        }

        struct WortmeldungView: Encodable {
            let id: String
            let speakerFullName: String
            let speakerFunction: String?
            let plainText: String
            let meetingDate: String?
            let parlGroupAbbreviation: String?
            let cantonAbbreviation: String?
            let councilName: String?
            let geschaeftId: Int?
            let geschaeftTitle: String?
            let businessShortNumber: String?
        }

        let views = wortmeldungen.map { wm in
            WortmeldungView(
                id: wm.id ?? "",
                speakerFullName: wm.speakerFullName,
                speakerFunction: wm.speakerFunction,
                plainText: String(wm.plainText.prefix(300)),
                meetingDate: wm.meetingDate,
                parlGroupAbbreviation: wm.parlGroupAbbreviation,
                cantonAbbreviation: wm.cantonAbbreviation,
                councilName: wm.councilName,
                geschaeftId: wm.$geschaeft.id,
                geschaeftTitle: wm.geschaeft?.title,
                businessShortNumber: wm.geschaeft?.businessShortNumber
            )
        }

        return try await req.view.render("wortmeldungen/index", Context(
            title: "Wortmeldungen",
            wortmeldungen: views,
            query: query,
            faction: faction,
            canton: canton,
            council: council,
            factions: allFactions,
            cantons: allCantons,
            totalCount: totalCount,
            page: clampedPage,
            totalPages: totalPages,
            currentUser: req.userContext
        ))
    }
}
