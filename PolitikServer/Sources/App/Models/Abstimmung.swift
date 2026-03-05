import Fluent
import Vapor

final class Abstimmung: Model, Content, @unchecked Sendable {
    static let schema = "abstimmungen"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @OptionalField(key: "business_number")
    var businessNumber: Int?

    @OptionalField(key: "business_short_number")
    var businessShortNumber: String?

    @OptionalField(key: "bill_title")
    var billTitle: String?

    @OptionalField(key: "subject")
    var subject: String?

    @OptionalField(key: "meaning_yes")
    var meaningYes: String?

    @OptionalField(key: "meaning_no")
    var meaningNo: String?

    @OptionalField(key: "vote_end")
    var voteEnd: Date?

    @OptionalField(key: "id_session")
    var idSession: Int?

    // Relationships
    @OptionalParent(key: "geschaeft_id")
    var geschaeft: Geschaeft?

    @Children(for: \.$abstimmung)
    var stimmabgaben: [Stimmabgabe]

    init() {}

    init(
        id: Int,
        businessNumber: Int?,
        businessShortNumber: String?,
        billTitle: String?,
        subject: String?,
        meaningYes: String?,
        meaningNo: String?,
        voteEnd: Date?,
        idSession: Int?
    ) {
        self.id = id
        self.businessNumber = businessNumber
        self.businessShortNumber = businessShortNumber
        self.billTitle = billTitle
        self.subject = subject
        self.meaningYes = meaningYes
        self.meaningNo = meaningNo
        self.voteEnd = voteEnd
        self.idSession = idSession
    }
}
