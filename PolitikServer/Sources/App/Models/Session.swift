import Fluent
import Vapor

final class Session: Model, Content, @unchecked Sendable {
    static let schema = "sessions"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "session_number")
    var sessionNumber: Int

    @Field(key: "session_name")
    var sessionName: String

    @Field(key: "abbreviation")
    var abbreviation: String

    @OptionalField(key: "start_date")
    var startDate: Date?

    @OptionalField(key: "end_date")
    var endDate: Date?

    @Field(key: "title")
    var title: String

    @Field(key: "type")
    var type: Int

    @Field(key: "type_name")
    var typeName: String

    @Field(key: "legislative_period_number")
    var legislativePeriodNumber: Int

    @Field(key: "is_synced")
    var isSynced: Bool

    @OptionalField(key: "last_sync_date")
    var lastSyncDate: Date?

    @Children(for: \.$session)
    var geschaefte: [Geschaeft]

    @Children(for: \.$session)
    var dailyReports: [DailyReport]

    init() {}

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
        self.isSynced = false
        self.lastSyncDate = nil
    }
}
