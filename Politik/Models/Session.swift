import Foundation
import SwiftData

@Model
final class Session {
    @Attribute(.unique) var id: Int
    var sessionNumber: Int
    var sessionName: String
    var abbreviation: String
    var startDate: Date?
    var endDate: Date?
    var title: String
    var type: Int
    var typeName: String
    var legislativePeriodNumber: Int
    var isSynced: Bool = false
    var lastSyncDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \Geschaeft.session)
    var geschaefte: [Geschaeft] = []

    init(
        id: Int,
        sessionNumber: Int,
        sessionName: String,
        abbreviation: String,
        startDate: Date?,
        endDate: Date?,
        title: String,
        type: Int,
        typeName: String,
        legislativePeriodNumber: Int
    ) {
        self.id = id
        self.sessionNumber = sessionNumber
        self.sessionName = sessionName
        self.abbreviation = abbreviation
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.type = type
        self.typeName = typeName
        self.legislativePeriodNumber = legislativePeriodNumber
    }
}
