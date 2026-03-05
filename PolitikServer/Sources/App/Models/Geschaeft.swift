import Fluent
import Vapor

final class Geschaeft: Model, Content, @unchecked Sendable {
    static let schema = "geschaefte"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "business_short_number")
    var businessShortNumber: String

    @Field(key: "title")
    var title: String

    @Field(key: "business_type_name")
    var businessTypeName: String

    @Field(key: "business_type_abbreviation")
    var businessTypeAbbreviation: String

    @Field(key: "business_status_text")
    var businessStatusText: String

    @OptionalField(key: "business_status_date")
    var businessStatusDate: Date?

    @OptionalField(key: "submission_date")
    var submissionDate: Date?

    @OptionalField(key: "submitted_by")
    var submittedBy: String?

    @OptionalField(key: "description_text")
    var descriptionText: String?

    @OptionalField(key: "submission_council_name")
    var submissionCouncilName: String?

    @OptionalField(key: "responsible_department_name")
    var responsibleDepartmentName: String?

    @OptionalField(key: "responsible_department_abbreviation")
    var responsibleDepartmentAbbreviation: String?

    @OptionalField(key: "tag_names")
    var tagNames: String?

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
    @OptionalParent(key: "session_id")
    var session: Session?

    @OptionalParent(key: "urheber_person_number")
    var urheber: Parlamentarier?

    @Children(for: \.$geschaeft)
    var wortmeldungen: [Wortmeldung]

    @Children(for: \.$geschaeft)
    var abstimmungen: [Abstimmung]

    var hasAnalysis: Bool {
        linksRechts != nil
    }

    init() {}

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
        tagNames: String?
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
    }
}
