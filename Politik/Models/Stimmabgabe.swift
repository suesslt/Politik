import Foundation
import SwiftData
import SwiftUI

@Model
final class Stimmabgabe {
    @Attribute(.unique) var id: Int
    var personNumber: Int
    var decision: Int
    var decisionText: String?

    var abstimmung: Abstimmung?
    var parlamentarier: Parlamentarier?

    var decisionDisplayText: String {
        switch decision {
        case 1: "Ja"
        case 2: "Nein"
        case 3: "Enthaltung"
        case 4: "Nicht teilgenommen"
        case 5: "Entschuldigt"
        case 6: "Präsident"
        default: decisionText ?? "Unbekannt"
        }
    }

    var decisionColor: Color {
        switch decision {
        case 1: .green
        case 2: .red
        case 3: .orange
        default: .gray
        }
    }

    init(
        id: Int,
        personNumber: Int,
        decision: Int,
        decisionText: String?,
        abstimmung: Abstimmung? = nil,
        parlamentarier: Parlamentarier? = nil
    ) {
        self.id = id
        self.personNumber = personNumber
        self.decision = decision
        self.decisionText = decisionText
        self.abstimmung = abstimmung
        self.parlamentarier = parlamentarier
    }
}
