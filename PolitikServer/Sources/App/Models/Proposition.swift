import Fluent
import Vapor

final class Proposition: Model, Content, @unchecked Sendable {
    static let schema = "propositions"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "key_message")
    var keyMessage: String

    @Field(key: "subject")
    var subject: String

    @OptionalField(key: "date_of_proposition")
    var dateOfProposition: Date?

    @Field(key: "source")
    var source: String

    @Field(key: "geschaeft_title")
    var geschaeftTitle: String

    @Field(key: "created_at")
    var createdAt: Date

    // Relationships
    @OptionalParent(key: "parlamentarier_person_number")
    var parlamentarier: Parlamentarier?

    @OptionalParent(key: "wortmeldung_id")
    var wortmeldung: Wortmeldung?

    init() {}

    init(
        keyMessage: String,
        subject: String,
        dateOfProposition: Date?,
        source: String,
        geschaeftTitle: String
    ) {
        self.keyMessage = keyMessage
        self.subject = subject
        self.dateOfProposition = dateOfProposition
        self.source = source
        self.geschaeftTitle = geschaeftTitle
        self.createdAt = Date()
    }
}
