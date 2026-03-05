import Fluent
import Vapor

final class PersonOccupation: Model, Content, @unchecked Sendable {
    static let schema = "person_occupations"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "person_number")
    var personNumber: Int

    @Field(key: "occupation_name")
    var occupationName: String

    @OptionalField(key: "employer")
    var employer: String?

    @OptionalField(key: "job_title")
    var jobTitle: String?

    // Relationships
    @OptionalParent(key: "parlamentarier_person_number")
    var parlamentarier: Parlamentarier?

    init() {}

    init(
        personNumber: Int,
        occupationName: String,
        employer: String?,
        jobTitle: String?
    ) {
        self.personNumber = personNumber
        self.occupationName = occupationName
        self.employer = employer
        self.jobTitle = jobTitle
    }
}
