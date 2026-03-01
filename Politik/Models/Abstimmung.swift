import Foundation
import SwiftData

@Model
final class Abstimmung {
    @Attribute(.unique) var id: Int
    var businessNumber: Int?
    var businessShortNumber: String?
    var billTitle: String?
    var subject: String?
    var meaningYes: String?
    var meaningNo: String?
    var voteEnd: Date?
    var idSession: Int?

    var geschaeft: Geschaeft?

    @Relationship(deleteRule: .cascade, inverse: \Stimmabgabe.abstimmung)
    var stimmabgaben: [Stimmabgabe] = []

    var jaCount: Int { stimmabgaben.filter { $0.decision == 1 }.count }
    var neinCount: Int { stimmabgaben.filter { $0.decision == 2 }.count }
    var enthaltungCount: Int { stimmabgaben.filter { $0.decision == 3 }.count }
    var nichtTeilgenommenCount: Int { stimmabgaben.filter { $0.decision == 4 }.count }
    var entschuldigtCount: Int { stimmabgaben.filter { $0.decision == 5 }.count }

    init(
        id: Int,
        businessNumber: Int?,
        businessShortNumber: String?,
        billTitle: String?,
        subject: String?,
        meaningYes: String?,
        meaningNo: String?,
        voteEnd: Date?,
        idSession: Int?,
        geschaeft: Geschaeft? = nil
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
        self.geschaeft = geschaeft
    }
}
