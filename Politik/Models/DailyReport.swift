import Foundation
import SwiftData

@Model
final class DailyReport {
    @Attribute(.unique) var id: UUID
    var sessionId: Int
    var sessionName: String
    var reportDate: Date
    var content: String
    var createdAt: Date

    var session: Session?

    init(
        sessionId: Int,
        sessionName: String,
        reportDate: Date,
        content: String,
        session: Session? = nil
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.reportDate = reportDate
        self.content = content
        self.createdAt = Date()
        self.session = session
    }
}
