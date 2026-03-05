import Foundation

// MARK: - OData Response Wrappers

struct ODataResponse<T: Decodable>: Decodable {
    let items: [T]
    let next: String?

    enum DKey: String, CodingKey { case d }
    enum ResultsKey: String, CodingKey { case results; case __next }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: DKey.self)
        do {
            items = try outer.decode([T].self, forKey: .d)
            next = nil
        } catch let arrayError {
            do {
                let inner = try outer.nestedContainer(keyedBy: ResultsKey.self, forKey: .d)
                items = try inner.decode([T].self, forKey: .results)
                next = try inner.decodeIfPresent(String.self, forKey: .__next)
            } catch {
                throw arrayError
            }
        }
    }
}

struct ODataSingleResponse<T: Decodable>: Decodable {
    let d: T
}

// MARK: - DTOs

struct SessionDTO: Decodable, Sendable {
    let ID: Int
    let SessionNumber: Int?
    let SessionName: String?
    let Abbreviation: String?
    let StartDate: String?
    let EndDate: String?
    let Title: String?
    let SessionType: Int?
    let TypeName: String?
    let LegislativePeriodNumber: Int?

    enum CodingKeys: String, CodingKey {
        case ID, SessionNumber, SessionName, Abbreviation, StartDate, EndDate, Title
        case SessionType = "Type"
        case TypeName, LegislativePeriodNumber
    }
}

struct GeschaeftDTO: Decodable, Sendable {
    let ID: Int
    let BusinessShortNumber: String?
    let Title: String?
    let BusinessTypeName: String?
    let BusinessTypeAbbreviation: String?
    let BusinessStatusText: String?
    let BusinessStatusDate: String?
    let SubmissionDate: String?
    let SubmittedBy: String?
    let Description: String?
    let SubmissionCouncilName: String?
    let ResponsibleDepartmentName: String?
    let ResponsibleDepartmentAbbreviation: String?
    let TagNames: String?
    let Modified: String?
}

struct TranscriptDTO: Decodable, Sendable {
    let ID: String?
    let PersonNumber: Int?
    let SpeakerFullName: String?
    let SpeakerFunction: String?
    let Text: String?
    let MeetingDate: String?
    let Start: String?
    let End: String?
    let CouncilName: String?
    let ParlGroupAbbreviation: String?
    let CantonAbbreviation: String?
    let SortOrder: Int?
    let TranscriptType: Int?

    enum CodingKeys: String, CodingKey {
        case ID, PersonNumber, SpeakerFullName, SpeakerFunction, Text, MeetingDate
        case Start, End, CouncilName, ParlGroupAbbreviation, CantonAbbreviation, SortOrder
        case TranscriptType = "Type"
    }
}

struct SubjectBusinessDTO: Decodable, Sendable {
    let IdSubject: String?
    let BusinessNumber: Int?
    let BusinessShortNumber: String?
    let Title: String?
    let SortOrder: Int?
}

struct MeetingDTO: Decodable, Sendable {
    let ID: String?
    let MeetingNumber: Int?
    let IdSession: Int?
    let Council: Int?
    let CouncilName: String?
    let CouncilAbbreviation: String?
    let Date: String?
    let Begin: String?
    let MeetingOrderText: String?
    let SortOrder: Int?
    let SessionName: String?
}

struct SubjectDTO: Decodable, Sendable {
    let ID: String?
    let IdMeeting: String?
    let SortOrder: Int?
    let VerbalixOid: Int?
}

struct BusinessRoleDTO: Decodable, Sendable {
    let ID: String?
    let Role: Int?
    let RoleName: String?
    let BusinessNumber: Int?
    let MemberCouncilNumber: Int?
}

struct ParlamentarierDTO: Decodable, Sendable {
    let ID: Int?
    let PersonNumber: Int?
    let FirstName: String?
    let LastName: String?
    let PartyAbbreviation: String?
    let ParlGroupAbbreviation: String?
    let CantonAbbreviation: String?
    let CouncilName: String?
    let CouncilAbbreviation: String?
    let Active: Bool?
    let DateOfBirth: String?
    let MaritalStatusText: String?
    let NumberOfChildren: Int?
    let BirthPlace_City: String?
    let BirthPlace_Canton: String?
    let Citizenship: String?
    let DateJoining: String?
    let DateLeaving: String?
    let DateElection: String?
    let MilitaryRankText: String?
    let PartyName: String?
    let ParlGroupName: String?
    let CantonName: String?
    let Nationality: String?
}

struct VoteDTO: Decodable, Sendable {
    let ID: Int
    let BusinessNumber: Int?
    let BusinessShortNumber: String?
    let BillTitle: String?
    let IdSession: Int?
    let Subject: String?
    let MeaningYes: String?
    let MeaningNo: String?
    let VoteEnd: String?
    let Modified: String?
}

struct VotingDTO: Decodable, Sendable {
    let ID: Int
    let IdVote: Int?
    let PersonNumber: Int?
    let Decision: Int?
    let DecisionText: String?
}

struct PersonInterestDTO: Decodable, Sendable {
    let PersonNumber: Int?
    let InterestName: String?
    let InterestTypeText: String?
    let FunctionInAgencyText: String?
    let Paid: Bool?
    let OrganizationTypeText: String?
}

struct PersonOccupationDTO: Decodable, Sendable {
    let PersonNumber: Int?
    let OccupationName: String?
    let Employer: String?
    let JobTitle: String?
}

// MARK: - Date Parsing

enum ODataDateParser {
    static func parse(_ dateString: String?) -> Date? {
        guard let dateString = dateString,
              let range = dateString.range(of: #"-?\d+"#, options: .regularExpression) else {
            return nil
        }
        let milliseconds = String(dateString[range])
        guard let ms = Double(milliseconds) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }
}

enum ODataDateFormatter {
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - Errors

enum ParlamentError: LocalizedError {
    case invalidURL
    case networkError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige URL"
        case .networkError: return "Netzwerkfehler"
        case .decodingError: return "Fehler beim Verarbeiten der Daten"
        }
    }
}
