import Foundation
import SwiftData

struct ParlamentService {
    private let baseURL = "https://ws.parlament.ch/odata.svc"

    // MARK: - Fetch Sessions

    func fetchSessions() async throws -> [SessionDTO] {
        let urlString = "\(baseURL)/Session?$filter=Language%20eq%20'DE'&$orderby=StartDate%20desc&$top=20&$format=json"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataResponse<SessionDTO>.self, from: data)
        return response.items
    }

    // MARK: - Fetch Geschaefte for a Session

    func fetchGeschaefte(sessionID: Int) async throws -> [GeschaeftDTO] {
        let urlString = "\(baseURL)/Session(ID=\(sessionID),Language='DE')/Businesses?$format=json&$select=ID,BusinessShortNumber,Title,BusinessTypeName,BusinessTypeAbbreviation,BusinessStatusText,BusinessStatusDate,SubmissionDate,SubmittedBy,Description,SubmissionCouncilName,ResponsibleDepartmentName,ResponsibleDepartmentAbbreviation,TagNames"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch Transcripts for a Geschaeft

    func fetchTranscripts(businessID: Int) async throws -> [TranscriptDTO] {
        let subjectURL = "\(baseURL)/SubjectBusiness?$filter=Language%20eq%20'DE'%20and%20BusinessNumber%20eq%20\(businessID)&$format=json&$select=IdSubject"
        let subjects: [SubjectBusinessDTO] = try await fetchAllPages(from: subjectURL)

        var allTranscripts: [TranscriptDTO] = []
        for subject in subjects {
            guard let idSubject = subject.IdSubject else { continue }
            let transcriptURL = "\(baseURL)/Transcript?$filter=Language%20eq%20'DE'%20and%20IdSubject%20eq%20\(idSubject)L&$format=json&$select=ID,PersonNumber,SpeakerFullName,SpeakerFunction,Text,MeetingDate,Start,End,CouncilName,ParlGroupAbbreviation,CantonAbbreviation,SortOrder,Type&$orderby=MeetingDate,SortOrder"
            let transcripts: [TranscriptDTO] = try await fetchAllPages(from: transcriptURL)
            allTranscripts.append(contentsOf: transcripts)
        }

        return allTranscripts
    }

    // MARK: - Decomposed Transcript Fetching (for sync)

    func fetchSubjectBusinesses(businessID: Int) async throws -> [SubjectBusinessDTO] {
        let urlString = "\(baseURL)/SubjectBusiness?$filter=Language%20eq%20'DE'%20and%20BusinessNumber%20eq%20\(businessID)&$format=json&$select=IdSubject"
        return try await fetchAllPages(from: urlString)
    }

    func fetchTranscriptsForSubject(idSubject: String) async throws -> [TranscriptDTO] {
        let urlString = "\(baseURL)/Transcript?$filter=Language%20eq%20'DE'%20and%20IdSubject%20eq%20\(idSubject)L&$format=json&$select=ID,PersonNumber,SpeakerFullName,SpeakerFunction,Text,MeetingDate,Start,End,CouncilName,ParlGroupAbbreviation,CantonAbbreviation,SortOrder,Type&$orderby=MeetingDate,SortOrder"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch BusinessRoles (Urheber) for a Geschaeft

    func fetchUrheber(businessID: Int) async throws -> BusinessRoleDTO? {
        let urlString = "\(baseURL)/Business(ID=\(businessID),Language='DE')/BusinessRoles?$format=json&$filter=Role%20eq%207&$select=ID,Role,RoleName,MemberCouncilNumber,BusinessNumber"
        let dtos: [BusinessRoleDTO] = try await fetchAllPages(from: urlString)
        return dtos.first { $0.MemberCouncilNumber != nil }
    }

    // MARK: - Fetch all active MemberCouncil

    func fetchAllParlamentarier() async throws -> [ParlamentarierDTO] {
        let urlString = "\(baseURL)/MemberCouncil?$filter=Language%20eq%20'DE'%20and%20Active%20eq%20true&$format=json&$select=ID,PersonNumber,FirstName,LastName,PartyAbbreviation,ParlGroupAbbreviation,CantonAbbreviation,CouncilName,CouncilAbbreviation,Active&$orderby=LastName,FirstName"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch a single MemberCouncil (basic)

    func fetchParlamentarier(personNumber: Int) async throws -> ParlamentarierDTO? {
        let urlString = "\(baseURL)/MemberCouncil(ID=\(personNumber),Language='DE')?$format=json&$select=ID,PersonNumber,FirstName,LastName,PartyAbbreviation,ParlGroupAbbreviation,CantonAbbreviation,CouncilName,CouncilAbbreviation,Active"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataSingleResponse<ParlamentarierDTO>.self, from: data)
        return response.d
    }

    // MARK: - Fetch enriched MemberCouncil detail

    func fetchParlamentarierDetail(personNumber: Int) async throws -> ParlamentarierDTO? {
        let urlString = "\(baseURL)/MemberCouncil(ID=\(personNumber),Language='DE')?$format=json&$select=ID,PersonNumber,FirstName,LastName,PartyAbbreviation,ParlGroupAbbreviation,CantonAbbreviation,CouncilName,CouncilAbbreviation,Active,DateOfBirth,MaritalStatusText,NumberOfChildren,BirthPlace_City,BirthPlace_Canton,Citizenship,DateJoining,DateLeaving,DateElection,MilitaryRankText,PartyName,ParlGroupName,CantonName,Nationality"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataSingleResponse<ParlamentarierDTO>.self, from: data)
        return response.d
    }

    // MARK: - Fetch single Business by ID

    func fetchBusiness(id: Int) async throws -> GeschaeftDTO? {
        let urlString = "\(baseURL)/Business(ID=\(id),Language='DE')?$format=json&$select=ID,BusinessShortNumber,Title,BusinessTypeName,BusinessTypeAbbreviation,BusinessStatusText,BusinessStatusDate,SubmissionDate,SubmittedBy,Description,SubmissionCouncilName,ResponsibleDepartmentName,ResponsibleDepartmentAbbreviation,TagNames"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataSingleResponse<GeschaeftDTO>.self, from: data)
        return response.d
    }

    // MARK: - Fetch Votes for a Session

    func fetchVotes(sessionID: Int) async throws -> [VoteDTO] {
        let urlString = "\(baseURL)/Vote?$filter=Language%20eq%20'DE'%20and%20IdSession%20eq%20\(sessionID)&$format=json&$select=ID,BusinessNumber,BusinessShortNumber,BillTitle,IdSession,Subject,MeaningYes,MeaningNo,VoteEnd"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch Votings (individual votes) for a Vote

    func fetchVotings(voteID: Int) async throws -> [VotingDTO] {
        let urlString = "\(baseURL)/Voting?$filter=Language%20eq%20'DE'%20and%20IdVote%20eq%20\(voteID)&$format=json&$select=ID,IdVote,PersonNumber,Decision,DecisionText"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch PersonInterests

    func fetchPersonInterests(personNumber: Int) async throws -> [PersonInterestDTO] {
        let urlString = "\(baseURL)/PersonInterest?$filter=Language%20eq%20'DE'%20and%20PersonNumber%20eq%20\(personNumber)&$format=json&$select=PersonNumber,InterestName,InterestTypeText,FunctionInAgencyText,Paid,OrganizationTypeText"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch PersonOccupations

    func fetchPersonOccupations(personNumber: Int) async throws -> [PersonOccupationDTO] {
        let urlString = "\(baseURL)/PersonOccupation?$filter=Language%20eq%20'DE'%20and%20PersonNumber%20eq%20\(personNumber)&$format=json&$select=PersonNumber,OccupationName,Employer,JobTitle"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Paging

    private func fetchAllPages<T: Decodable>(from urlString: String) async throws -> [T] {
        var allResults: [T] = []
        var nextURL: String? = urlString

        while let currentURL = nextURL {
            let data = try await fetchData(from: currentURL)
            let response = try JSONDecoder().decode(ODataResponse<T>.self, from: data)
            allResults.append(contentsOf: response.items)
            nextURL = response.next
        }

        return allResults
    }

    // MARK: - Networking

    private func fetchData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw ParlamentError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ParlamentError.networkError
        }
        return data
    }
}

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
    // Enriched detail fields
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
              let range = dateString.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        let milliseconds = String(dateString[range])
        guard let ms = Double(milliseconds) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
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
