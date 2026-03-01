import Foundation
import SwiftData

@Model
final class Proposition {
    @Attribute(.unique) var id: UUID = UUID()
    var keyMessage: String = ""
    var subject: String = ""
    var dateOfProposition: Date?
    var source: String = ""
    var geschaeft: String = ""
    var createdAt: Date = Date()

    var parlamentarier: Parlamentarier?
    var wortmeldung: Wortmeldung?

    init(
        keyMessage: String,
        subject: String,
        dateOfProposition: Date?,
        source: String,
        geschaeft: String,
        parlamentarier: Parlamentarier? = nil,
        wortmeldung: Wortmeldung? = nil
    ) {
        self.id = UUID()
        self.keyMessage = keyMessage
        self.subject = subject
        self.dateOfProposition = dateOfProposition
        self.source = source
        self.geschaeft = geschaeft
        self.createdAt = Date()
        self.parlamentarier = parlamentarier
        self.wortmeldung = wortmeldung
    }
}
