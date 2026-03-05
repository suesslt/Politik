import Fluent
import Vapor

final class DailyReport: Model, Content, @unchecked Sendable {
    static let schema = "daily_reports"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "session_id")
    var sessionId: Int

    @Field(key: "session_name")
    var sessionName: String

    @Field(key: "report_date")
    var reportDate: Date

    @Field(key: "content")
    var content: String

    @Field(key: "created_at")
    var createdAt: Date

    // Relationships
    @OptionalParent(key: "session_ref_id")
    var session: Session?

    init() {}

    init(
        sessionId: Int,
        sessionName: String,
        reportDate: Date,
        content: String
    ) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.reportDate = reportDate
        self.content = content
        self.createdAt = Date()
    }
}
