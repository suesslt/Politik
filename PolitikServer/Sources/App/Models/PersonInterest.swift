import Fluent
import Vapor

final class PersonInterest: Model, Content, @unchecked Sendable {
    static let schema = "person_interests"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "person_number")
    var personNumber: Int

    @Field(key: "interest_name")
    var interestName: String

    @OptionalField(key: "interest_type_text")
    var interestTypeText: String?

    @OptionalField(key: "function_in_agency_text")
    var functionInAgencyText: String?

    @OptionalField(key: "paid")
    var paid: Bool?

    @OptionalField(key: "organization_type_text")
    var organizationTypeText: String?

    // Relationships
    @OptionalParent(key: "parlamentarier_person_number")
    var parlamentarier: Parlamentarier?

    init() {}

    init(
        personNumber: Int,
        interestName: String,
        interestTypeText: String?,
        functionInAgencyText: String?,
        paid: Bool?,
        organizationTypeText: String?
    ) {
        self.personNumber = personNumber
        self.interestName = interestName
        self.interestTypeText = interestTypeText
        self.functionInAgencyText = functionInAgencyText
        self.paid = paid
        self.organizationTypeText = organizationTypeText
    }
}
