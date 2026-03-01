import Foundation
import SwiftData

@Model
final class Parlamentarier {
    @Attribute(.unique) var personNumber: Int
    var firstName: String
    var lastName: String
    var partyAbbreviation: String?
    var parlGroupAbbreviation: String?
    var cantonAbbreviation: String?
    var councilName: String?
    var councilAbbreviation: String?
    var isActive: Bool

    // Enriched details (loaded lazily from MemberCouncil API)
    var dateOfBirth: Date?
    var maritalStatusText: String?
    var numberOfChildren: Int?
    var birthPlaceCity: String?
    var birthPlaceCanton: String?
    var citizenship: String?
    var nationality: String?
    var dateJoining: Date?
    var dateLeaving: Date?
    var dateElection: Date?
    var militaryRankText: String?
    var partyName: String?
    var parlGroupName: String?
    var cantonName: String?
    var isDetailLoaded: Bool = false

    // Claude AI analysis results
    var linksRechts: Double?
    var konservativLiberal: Double?
    var liberaleWirtschaft: Double?
    var innovativerStandort: Double?
    var unabhaengigeStromversorgung: Double?
    var staerkeResilienz: Double?
    var schlankerStaat: Double?

    var hasAnalysis: Bool { linksRechts != nil }

    @Relationship(deleteRule: .nullify, inverse: \Geschaeft.urheber)
    var geschaefte: [Geschaeft] = []

    @Relationship(deleteRule: .cascade, inverse: \Wortmeldung.parlamentarier)
    var wortmeldungen: [Wortmeldung] = []

    @Relationship(deleteRule: .cascade, inverse: \Stimmabgabe.parlamentarier)
    var stimmabgaben: [Stimmabgabe] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonInterest.parlamentarier)
    var interests: [PersonInterest] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonOccupation.parlamentarier)
    var occupations: [PersonOccupation] = []

    @Relationship(deleteRule: .cascade, inverse: \Proposition.parlamentarier)
    var propositions: [Proposition] = []

    var fullName: String {
        "\(firstName) \(lastName)"
    }

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
        self.personNumber = personNumber
        self.firstName = firstName
        self.lastName = lastName
        self.partyAbbreviation = partyAbbreviation
        self.parlGroupAbbreviation = parlGroupAbbreviation
        self.cantonAbbreviation = cantonAbbreviation
        self.councilName = councilName
        self.councilAbbreviation = councilAbbreviation
        self.isActive = isActive
    }
}
