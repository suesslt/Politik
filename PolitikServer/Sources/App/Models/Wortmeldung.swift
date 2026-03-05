import Fluent
import Vapor

final class Wortmeldung: Model, Content, @unchecked Sendable {
    static let schema = "wortmeldungen"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "speaker_full_name")
    var speakerFullName: String

    @OptionalField(key: "speaker_function")
    var speakerFunction: String?

    @Field(key: "text")
    var text: String

    @OptionalField(key: "meeting_date")
    var meetingDate: String?

    @OptionalField(key: "parl_group_abbreviation")
    var parlGroupAbbreviation: String?

    @OptionalField(key: "canton_abbreviation")
    var cantonAbbreviation: String?

    @OptionalField(key: "council_name")
    var councilName: String?

    @Field(key: "sort_order")
    var sortOrder: Int

    @Field(key: "type")
    var type: Int

    @OptionalField(key: "start_time")
    var startTime: Date?

    @OptionalField(key: "end_time")
    var endTime: Date?

    @Field(key: "is_proposition_extracted")
    var isPropositionExtracted: Bool

    // Relationships
    @OptionalParent(key: "geschaeft_id")
    var geschaeft: Geschaeft?

    @OptionalParent(key: "parlamentarier_person_number")
    var parlamentarier: Parlamentarier?

    @Children(for: \.$wortmeldung)
    var propositions: [Proposition]

    var plainText: String {
        var result = text
        // Strip HTML tags
        while let range = result.range(of: "<[^>]+>", options: .regularExpression) {
            result.removeSubrange(range)
        }
        // Clean up whitespace
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isRede: Bool {
        type == 1
    }

    init() {}

    init(
        id: String,
        speakerFullName: String,
        speakerFunction: String?,
        text: String,
        meetingDate: String?,
        parlGroupAbbreviation: String?,
        cantonAbbreviation: String?,
        councilName: String?,
        sortOrder: Int,
        type: Int,
        startTime: Date?,
        endTime: Date?
    ) {
        self.id = id
        self.speakerFullName = speakerFullName
        self.speakerFunction = speakerFunction
        self.text = text
        self.meetingDate = meetingDate
        self.parlGroupAbbreviation = parlGroupAbbreviation
        self.cantonAbbreviation = cantonAbbreviation
        self.councilName = councilName
        self.sortOrder = sortOrder
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.isPropositionExtracted = false
    }
}
