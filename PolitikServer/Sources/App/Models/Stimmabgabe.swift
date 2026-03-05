import Fluent
import Vapor

final class Stimmabgabe: Model, Content, @unchecked Sendable {
    static let schema = "stimmabgaben"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "person_number")
    var personNumber: Int

    @Field(key: "decision")
    var decision: Int

    @OptionalField(key: "decision_text")
    var decisionText: String?

    // Relationships
    @OptionalParent(key: "abstimmung_id")
    var abstimmung: Abstimmung?

    @OptionalParent(key: "parlamentarier_person_number")
    var parlamentarier: Parlamentarier?

    var decisionDisplayText: String {
        switch decision {
        case 1: return "Ja"
        case 2: return "Nein"
        case 3: return "Enthaltung"
        case 4: return "Nicht teilgenommen"
        case 5: return "Entschuldigt"
        case 6: return "Präsident"
        default: return "Unbekannt"
        }
    }

    init() {}

    init(
        id: Int,
        personNumber: Int,
        decision: Int,
        decisionText: String?
    ) {
        self.id = id
        self.personNumber = personNumber
        self.decision = decision
        self.decisionText = decisionText
    }
}
