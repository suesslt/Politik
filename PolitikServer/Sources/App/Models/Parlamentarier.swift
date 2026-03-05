import Fluent
import Vapor

final class Parlamentarier: Model, Content, @unchecked Sendable {
    static let schema = "parlamentarier"

    @ID(custom: "person_number", generatedBy: .user)
    var id: Int?

    @Field(key: "first_name")
    var firstName: String

    @Field(key: "last_name")
    var lastName: String

    @OptionalField(key: "party_abbreviation")
    var partyAbbreviation: String?

    @OptionalField(key: "parl_group_abbreviation")
    var parlGroupAbbreviation: String?

    @OptionalField(key: "canton_abbreviation")
    var cantonAbbreviation: String?

    @OptionalField(key: "council_name")
    var councilName: String?

    @OptionalField(key: "council_abbreviation")
    var councilAbbreviation: String?

    @Field(key: "is_active")
    var isActive: Bool

    // Enriched detail fields
    @OptionalField(key: "date_of_birth")
    var dateOfBirth: Date?

    @OptionalField(key: "marital_status_text")
    var maritalStatusText: String?

    @OptionalField(key: "number_of_children")
    var numberOfChildren: Int?

    @OptionalField(key: "birth_place_city")
    var birthPlaceCity: String?

    @OptionalField(key: "birth_place_canton")
    var birthPlaceCanton: String?

    @OptionalField(key: "citizenship")
    var citizenship: String?

    @OptionalField(key: "nationality")
    var nationality: String?

    @OptionalField(key: "date_joining")
    var dateJoining: Date?

    @OptionalField(key: "date_leaving")
    var dateLeaving: Date?

    @OptionalField(key: "date_election")
    var dateElection: Date?

    @OptionalField(key: "military_rank_text")
    var militaryRankText: String?

    @OptionalField(key: "party_name")
    var partyName: String?

    @OptionalField(key: "parl_group_name")
    var parlGroupName: String?

    @OptionalField(key: "canton_name")
    var cantonName: String?

    @Field(key: "is_detail_loaded")
    var isDetailLoaded: Bool

    // Analysis scores
    @OptionalField(key: "links_rechts")
    var linksRechts: Double?

    @OptionalField(key: "konservativ_liberal")
    var konservativLiberal: Double?

    @OptionalField(key: "liberale_wirtschaft")
    var liberaleWirtschaft: Double?

    @OptionalField(key: "innovativer_standort")
    var innovativerStandort: Double?

    @OptionalField(key: "unabhaengige_stromversorgung")
    var unabhaengigeStromversorgung: Double?

    @OptionalField(key: "staerke_resilienz")
    var staerkeResilienz: Double?

    @OptionalField(key: "schlanker_staat")
    var schlankerStaat: Double?

    // Relationships
    @Children(for: \.$urheber)
    var geschaefte: [Geschaeft]

    @Children(for: \.$parlamentarier)
    var wortmeldungen: [Wortmeldung]

    @Children(for: \.$parlamentarier)
    var stimmabgaben: [Stimmabgabe]

    @Children(for: \.$parlamentarier)
    var interests: [PersonInterest]

    @Children(for: \.$parlamentarier)
    var occupations: [PersonOccupation]

    @Children(for: \.$parlamentarier)
    var propositions: [Proposition]

    var hasAnalysis: Bool {
        linksRechts != nil
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init() {}

    init(
        personNumber: Int,
        firstName: String,
        lastName: String,
        partyAbbreviation: String?,
        parlGroupAbbreviation: String?,
        cantonAbbreviation: String?,
        councilName: String?,
        councilAbbreviation: String?,
        isActive: Bool
    ) {
        self.id = personNumber
        self.firstName = firstName
        self.lastName = lastName
        self.partyAbbreviation = partyAbbreviation
        self.parlGroupAbbreviation = parlGroupAbbreviation
        self.cantonAbbreviation = cantonAbbreviation
        self.councilName = councilName
        self.councilAbbreviation = councilAbbreviation
        self.isActive = isActive
        self.isDetailLoaded = false
    }
}
