import Foundation
import SwiftData

@Model
final class Wortmeldung {
    @Attribute(.unique) var id: String
    var speakerFullName: String
    var speakerFunction: String?
    var text: String
    var meetingDate: String?
    var parlGroupAbbreviation: String?
    var cantonAbbreviation: String?
    var councilName: String?
    var sortOrder: Int
    var type: Int
    var startTime: Date?
    var endTime: Date?

    var isPropositionExtracted: Bool = false

    var geschaeft: Geschaeft?
    var parlamentarier: Parlamentarier?

    @Relationship(deleteRule: .cascade, inverse: \Proposition.wortmeldung)
    var propositions: [Proposition] = []

    /// Strips HTML tags from the text for display
    var plainText: String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[GZ\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[NB\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[NAM\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isRede: Bool { type == 1 }

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
        endTime: Date?,
        geschaeft: Geschaeft? = nil,
        parlamentarier: Parlamentarier? = nil
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
        self.geschaeft = geschaeft
        self.parlamentarier = parlamentarier
    }
}
