import Foundation
import SwiftData

@Model
final class Geschaeft {
    @Attribute(.unique) var id: Int
    var businessShortNumber: String
    var title: String
    var businessTypeName: String
    var businessTypeAbbreviation: String
    var businessStatusText: String
    var businessStatusDate: Date?
    var submissionDate: Date?
    var submittedBy: String?
    var descriptionText: String?
    var submissionCouncilName: String?
    var responsibleDepartmentName: String?
    var responsibleDepartmentAbbreviation: String?
    var tagNames: String?

    // Claude AI analysis results
    var linksRechts: Double?
    var konservativLiberal: Double?
    var liberaleWirtschaft: Double?
    var innovativerStandort: Double?
    var unabhaengigeStromversorgung: Double?
    var staerkeResilienz: Double?
    var schlankerStaat: Double?

    var hasAnalysis: Bool { linksRechts != nil }

    var session: Session?
    var urheber: Parlamentarier?

    @Relationship(deleteRule: .cascade, inverse: \Wortmeldung.geschaeft)
    var wortmeldungen: [Wortmeldung] = []

    @Relationship(deleteRule: .cascade, inverse: \Abstimmung.geschaeft)
    var abstimmungen: [Abstimmung] = []

    init(
        id: Int,
        businessShortNumber: String,
        title: String,
        businessTypeName: String,
        businessTypeAbbreviation: String,
        businessStatusText: String,
        businessStatusDate: Date?,
        submissionDate: Date?,
        submittedBy: String?,
        descriptionText: String?,
        submissionCouncilName: String?,
        responsibleDepartmentName: String?,
        responsibleDepartmentAbbreviation: String?,
        tagNames: String?,
        session: Session? = nil,
        urheber: Parlamentarier? = nil
    ) {
        self.id = id
        self.businessShortNumber = businessShortNumber
        self.title = title
        self.businessTypeName = businessTypeName
        self.businessTypeAbbreviation = businessTypeAbbreviation
        self.businessStatusText = businessStatusText
        self.businessStatusDate = businessStatusDate
        self.submissionDate = submissionDate
        self.submittedBy = submittedBy
        self.descriptionText = descriptionText
        self.submissionCouncilName = submissionCouncilName
        self.responsibleDepartmentName = responsibleDepartmentName
        self.responsibleDepartmentAbbreviation = responsibleDepartmentAbbreviation
        self.tagNames = tagNames
        self.session = session
        self.urheber = urheber
    }
}
