import Foundation
import SwiftData

// MARK: - Export Container

struct ExportContainer: Codable {
    let exportDate: Date
    let version: Int
    var sessions: [ExportSession]
    var geschaefte: [ExportGeschaeft]
    var parlamentarier: [ExportParlamentarier]
    var wortmeldungen: [ExportWortmeldung]
    var abstimmungen: [ExportAbstimmung]
    var stimmabgaben: [ExportStimmabgabe]
    var personInterests: [ExportPersonInterest]
    var personOccupations: [ExportPersonOccupation]
}

// MARK: - Export DTOs

struct ExportSession: Codable {
    let id: Int
    let sessionNumber: Int
    let sessionName: String
    let abbreviation: String
    let startDate: Date?
    let endDate: Date?
    let title: String
    let type: Int
    let typeName: String
    let legislativePeriodNumber: Int
    let isSynced: Bool
}

struct ExportGeschaeft: Codable {
    let id: Int
    let businessShortNumber: String
    let title: String
    let businessTypeName: String
    let businessTypeAbbreviation: String
    let businessStatusText: String
    let businessStatusDate: Date?
    let submissionDate: Date?
    let submittedBy: String?
    let descriptionText: String?
    let submissionCouncilName: String?
    let responsibleDepartmentName: String?
    let responsibleDepartmentAbbreviation: String?
    let tagNames: String?
    // Claude AI analysis
    let linksRechts: Double?
    let konservativLiberal: Double?
    let liberaleWirtschaft: Double?
    let innovativerStandort: Double?
    let unabhaengigeStromversorgung: Double?
    let staerkeResilienz: Double?
    let schlankerStaat: Double?
    // Relationships as IDs
    let sessionID: Int?
    let urheberPersonNumber: Int?
}

struct ExportParlamentarier: Codable {
    let personNumber: Int
    let firstName: String
    let lastName: String
    let partyAbbreviation: String?
    let parlGroupAbbreviation: String?
    let cantonAbbreviation: String?
    let councilName: String?
    let councilAbbreviation: String?
    let isActive: Bool
    // Enriched details
    let dateOfBirth: Date?
    let maritalStatusText: String?
    let numberOfChildren: Int?
    let birthPlaceCity: String?
    let birthPlaceCanton: String?
    let citizenship: String?
    let nationality: String?
    let dateJoining: Date?
    let dateLeaving: Date?
    let dateElection: Date?
    let militaryRankText: String?
    let partyName: String?
    let parlGroupName: String?
    let cantonName: String?
    let isDetailLoaded: Bool
    // Claude AI analysis
    let linksRechts: Double?
    let konservativLiberal: Double?
    let liberaleWirtschaft: Double?
    let innovativerStandort: Double?
    let unabhaengigeStromversorgung: Double?
    let staerkeResilienz: Double?
    let schlankerStaat: Double?
}

struct ExportWortmeldung: Codable {
    let id: String
    let speakerFullName: String
    let speakerFunction: String?
    let text: String
    let meetingDate: String?
    let parlGroupAbbreviation: String?
    let cantonAbbreviation: String?
    let councilName: String?
    let sortOrder: Int
    let type: Int
    let startTime: Date?
    let endTime: Date?
    // Relationships as IDs
    let geschaeftID: Int?
    let parlamentarierPersonNumber: Int?
}

struct ExportAbstimmung: Codable {
    let id: Int
    let businessNumber: Int?
    let businessShortNumber: String?
    let billTitle: String?
    let subject: String?
    let meaningYes: String?
    let meaningNo: String?
    let voteEnd: Date?
    let idSession: Int?
    // Relationship as ID
    let geschaeftID: Int?
}

struct ExportStimmabgabe: Codable {
    let id: Int
    let personNumber: Int
    let decision: Int
    let decisionText: String?
    // Relationships as IDs
    let abstimmungID: Int?
    let parlamentarierPersonNumber: Int?
}

struct ExportPersonInterest: Codable {
    let personNumber: Int
    let interestName: String
    let interestTypeText: String?
    let functionInAgencyText: String?
    let paid: Bool?
    let organizationTypeText: String?
    // Relationship as ID
    let parlamentarierPersonNumber: Int?
}

struct ExportPersonOccupation: Codable {
    let personNumber: Int
    let occupationName: String
    let employer: String?
    let jobTitle: String?
    // Relationship as ID
    let parlamentarierPersonNumber: Int?
}

// MARK: - Export/Import Service

@MainActor @Observable
final class DataExportImportService {

    enum Phase: Equatable {
        case idle
        case exporting
        case importing(step: String)
        case completed(message: String)
        case error(message: String)
    }

    var phase: Phase = .idle

    // MARK: - Export

    func exportAll(modelContext: ModelContext) throws -> Data {
        phase = .exporting

        let sessions = try modelContext.fetch(FetchDescriptor<Session>())
        let geschaefte = try modelContext.fetch(FetchDescriptor<Geschaeft>())
        let parlamentarierList = try modelContext.fetch(FetchDescriptor<Parlamentarier>())
        let wortmeldungen = try modelContext.fetch(FetchDescriptor<Wortmeldung>())
        let abstimmungen = try modelContext.fetch(FetchDescriptor<Abstimmung>())
        let stimmabgaben = try modelContext.fetch(FetchDescriptor<Stimmabgabe>())
        let personInterests = try modelContext.fetch(FetchDescriptor<PersonInterest>())
        let personOccupations = try modelContext.fetch(FetchDescriptor<PersonOccupation>())

        let container = ExportContainer(
            exportDate: Date(),
            version: 1,
            sessions: sessions.map { s in
                ExportSession(
                    id: s.id,
                    sessionNumber: s.sessionNumber,
                    sessionName: s.sessionName,
                    abbreviation: s.abbreviation,
                    startDate: s.startDate,
                    endDate: s.endDate,
                    title: s.title,
                    type: s.type,
                    typeName: s.typeName,
                    legislativePeriodNumber: s.legislativePeriodNumber,
                    isSynced: s.isSynced
                )
            },
            geschaefte: geschaefte.map { g in
                ExportGeschaeft(
                    id: g.id,
                    businessShortNumber: g.businessShortNumber,
                    title: g.title,
                    businessTypeName: g.businessTypeName,
                    businessTypeAbbreviation: g.businessTypeAbbreviation,
                    businessStatusText: g.businessStatusText,
                    businessStatusDate: g.businessStatusDate,
                    submissionDate: g.submissionDate,
                    submittedBy: g.submittedBy,
                    descriptionText: g.descriptionText,
                    submissionCouncilName: g.submissionCouncilName,
                    responsibleDepartmentName: g.responsibleDepartmentName,
                    responsibleDepartmentAbbreviation: g.responsibleDepartmentAbbreviation,
                    tagNames: g.tagNames,
                    linksRechts: g.linksRechts,
                    konservativLiberal: g.konservativLiberal,
                    liberaleWirtschaft: g.liberaleWirtschaft,
                    innovativerStandort: g.innovativerStandort,
                    unabhaengigeStromversorgung: g.unabhaengigeStromversorgung,
                    staerkeResilienz: g.staerkeResilienz,
                    schlankerStaat: g.schlankerStaat,
                    sessionID: g.session?.id,
                    urheberPersonNumber: g.urheber?.personNumber
                )
            },
            parlamentarier: parlamentarierList.map { p in
                ExportParlamentarier(
                    personNumber: p.personNumber,
                    firstName: p.firstName,
                    lastName: p.lastName,
                    partyAbbreviation: p.partyAbbreviation,
                    parlGroupAbbreviation: p.parlGroupAbbreviation,
                    cantonAbbreviation: p.cantonAbbreviation,
                    councilName: p.councilName,
                    councilAbbreviation: p.councilAbbreviation,
                    isActive: p.isActive,
                    dateOfBirth: p.dateOfBirth,
                    maritalStatusText: p.maritalStatusText,
                    numberOfChildren: p.numberOfChildren,
                    birthPlaceCity: p.birthPlaceCity,
                    birthPlaceCanton: p.birthPlaceCanton,
                    citizenship: p.citizenship,
                    nationality: p.nationality,
                    dateJoining: p.dateJoining,
                    dateLeaving: p.dateLeaving,
                    dateElection: p.dateElection,
                    militaryRankText: p.militaryRankText,
                    partyName: p.partyName,
                    parlGroupName: p.parlGroupName,
                    cantonName: p.cantonName,
                    isDetailLoaded: p.isDetailLoaded,
                    linksRechts: p.linksRechts,
                    konservativLiberal: p.konservativLiberal,
                    liberaleWirtschaft: p.liberaleWirtschaft,
                    innovativerStandort: p.innovativerStandort,
                    unabhaengigeStromversorgung: p.unabhaengigeStromversorgung,
                    staerkeResilienz: p.staerkeResilienz,
                    schlankerStaat: p.schlankerStaat
                )
            },
            wortmeldungen: wortmeldungen.map { w in
                ExportWortmeldung(
                    id: w.id,
                    speakerFullName: w.speakerFullName,
                    speakerFunction: w.speakerFunction,
                    text: w.text,
                    meetingDate: w.meetingDate,
                    parlGroupAbbreviation: w.parlGroupAbbreviation,
                    cantonAbbreviation: w.cantonAbbreviation,
                    councilName: w.councilName,
                    sortOrder: w.sortOrder,
                    type: w.type,
                    startTime: w.startTime,
                    endTime: w.endTime,
                    geschaeftID: w.geschaeft?.id,
                    parlamentarierPersonNumber: w.parlamentarier?.personNumber
                )
            },
            abstimmungen: abstimmungen.map { a in
                ExportAbstimmung(
                    id: a.id,
                    businessNumber: a.businessNumber,
                    businessShortNumber: a.businessShortNumber,
                    billTitle: a.billTitle,
                    subject: a.subject,
                    meaningYes: a.meaningYes,
                    meaningNo: a.meaningNo,
                    voteEnd: a.voteEnd,
                    idSession: a.idSession,
                    geschaeftID: a.geschaeft?.id
                )
            },
            stimmabgaben: stimmabgaben.map { s in
                ExportStimmabgabe(
                    id: s.id,
                    personNumber: s.personNumber,
                    decision: s.decision,
                    decisionText: s.decisionText,
                    abstimmungID: s.abstimmung?.id,
                    parlamentarierPersonNumber: s.parlamentarier?.personNumber
                )
            },
            personInterests: personInterests.map { pi in
                ExportPersonInterest(
                    personNumber: pi.personNumber,
                    interestName: pi.interestName,
                    interestTypeText: pi.interestTypeText,
                    functionInAgencyText: pi.functionInAgencyText,
                    paid: pi.paid,
                    organizationTypeText: pi.organizationTypeText,
                    parlamentarierPersonNumber: pi.parlamentarier?.personNumber
                )
            },
            personOccupations: personOccupations.map { po in
                ExportPersonOccupation(
                    personNumber: po.personNumber,
                    occupationName: po.occupationName,
                    employer: po.employer,
                    jobTitle: po.jobTitle,
                    parlamentarierPersonNumber: po.parlamentarier?.personNumber
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(container)

        let counts = """
        \(sessions.count) Sessionen, \(geschaefte.count) Geschäfte, \
        \(parlamentarierList.count) Parlamentarier, \(wortmeldungen.count) Wortmeldungen, \
        \(abstimmungen.count) Abstimmungen, \(stimmabgaben.count) Stimmabgaben, \
        \(personInterests.count) Interessen, \(personOccupations.count) Berufe
        """
        phase = .completed(message: "Export abgeschlossen: \(counts)")
        return data
    }

    // MARK: - Import Preview

    func previewImport(from data: Data) throws -> ExportContainer {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportContainer.self, from: data)
    }

    // MARK: - Import

    func importAll(from data: Data, modelContext: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let container = try decoder.decode(ExportContainer.self, from: data)

        // Step 1: Delete all existing data
        phase = .importing(step: "Bestehende Daten löschen…")
        try modelContext.delete(model: Stimmabgabe.self)
        try modelContext.delete(model: PersonInterest.self)
        try modelContext.delete(model: PersonOccupation.self)
        try modelContext.delete(model: Wortmeldung.self)
        try modelContext.delete(model: Abstimmung.self)
        try modelContext.delete(model: Geschaeft.self)
        try modelContext.delete(model: Parlamentarier.self)
        try modelContext.delete(model: Session.self)
        try modelContext.save()

        // Step 2: Import Sessions (no dependencies)
        phase = .importing(step: "Sessionen importieren (\(container.sessions.count))…")
        var sessionLookup: [Int: Session] = [:]
        for dto in container.sessions {
            let session = Session(
                id: dto.id,
                sessionNumber: dto.sessionNumber,
                sessionName: dto.sessionName,
                abbreviation: dto.abbreviation,
                startDate: dto.startDate,
                endDate: dto.endDate,
                title: dto.title,
                type: dto.type,
                typeName: dto.typeName,
                legislativePeriodNumber: dto.legislativePeriodNumber
            )
            session.isSynced = dto.isSynced
            modelContext.insert(session)
            sessionLookup[dto.id] = session
        }
        try modelContext.save()

        // Step 3: Import Parlamentarier (no dependencies)
        phase = .importing(step: "Parlamentarier importieren (\(container.parlamentarier.count))…")
        var parlamentarierLookup: [Int: Parlamentarier] = [:]
        for dto in container.parlamentarier {
            let person = Parlamentarier(
                personNumber: dto.personNumber,
                firstName: dto.firstName,
                lastName: dto.lastName,
                partyAbbreviation: dto.partyAbbreviation,
                parlGroupAbbreviation: dto.parlGroupAbbreviation,
                cantonAbbreviation: dto.cantonAbbreviation,
                councilName: dto.councilName,
                councilAbbreviation: dto.councilAbbreviation,
                isActive: dto.isActive
            )
            // Enriched fields
            person.dateOfBirth = dto.dateOfBirth
            person.maritalStatusText = dto.maritalStatusText
            person.numberOfChildren = dto.numberOfChildren
            person.birthPlaceCity = dto.birthPlaceCity
            person.birthPlaceCanton = dto.birthPlaceCanton
            person.citizenship = dto.citizenship
            person.nationality = dto.nationality
            person.dateJoining = dto.dateJoining
            person.dateLeaving = dto.dateLeaving
            person.dateElection = dto.dateElection
            person.militaryRankText = dto.militaryRankText
            person.partyName = dto.partyName
            person.parlGroupName = dto.parlGroupName
            person.cantonName = dto.cantonName
            person.isDetailLoaded = dto.isDetailLoaded
            // Claude AI analysis
            person.linksRechts = dto.linksRechts
            person.konservativLiberal = dto.konservativLiberal
            person.liberaleWirtschaft = dto.liberaleWirtschaft
            person.innovativerStandort = dto.innovativerStandort
            person.unabhaengigeStromversorgung = dto.unabhaengigeStromversorgung
            person.staerkeResilienz = dto.staerkeResilienz
            person.schlankerStaat = dto.schlankerStaat
            modelContext.insert(person)
            parlamentarierLookup[dto.personNumber] = person
        }
        try modelContext.save()

        // Step 4: Import Geschaefte (→ Session, Parlamentarier)
        phase = .importing(step: "Geschäfte importieren (\(container.geschaefte.count))…")
        var geschaeftLookup: [Int: Geschaeft] = [:]
        for dto in container.geschaefte {
            let geschaeft = Geschaeft(
                id: dto.id,
                businessShortNumber: dto.businessShortNumber,
                title: dto.title,
                businessTypeName: dto.businessTypeName,
                businessTypeAbbreviation: dto.businessTypeAbbreviation,
                businessStatusText: dto.businessStatusText,
                businessStatusDate: dto.businessStatusDate,
                submissionDate: dto.submissionDate,
                submittedBy: dto.submittedBy,
                descriptionText: dto.descriptionText,
                submissionCouncilName: dto.submissionCouncilName,
                responsibleDepartmentName: dto.responsibleDepartmentName,
                responsibleDepartmentAbbreviation: dto.responsibleDepartmentAbbreviation,
                tagNames: dto.tagNames,
                session: dto.sessionID.flatMap { sessionLookup[$0] },
                urheber: dto.urheberPersonNumber.flatMap { parlamentarierLookup[$0] }
            )
            // Claude AI analysis
            geschaeft.linksRechts = dto.linksRechts
            geschaeft.konservativLiberal = dto.konservativLiberal
            geschaeft.liberaleWirtschaft = dto.liberaleWirtschaft
            geschaeft.innovativerStandort = dto.innovativerStandort
            geschaeft.unabhaengigeStromversorgung = dto.unabhaengigeStromversorgung
            geschaeft.staerkeResilienz = dto.staerkeResilienz
            geschaeft.schlankerStaat = dto.schlankerStaat
            modelContext.insert(geschaeft)
            geschaeftLookup[dto.id] = geschaeft
        }
        try modelContext.save()

        // Step 5: Import Wortmeldungen (→ Geschaeft, Parlamentarier)
        phase = .importing(step: "Wortmeldungen importieren (\(container.wortmeldungen.count))…")
        for (index, dto) in container.wortmeldungen.enumerated() {
            let wortmeldung = Wortmeldung(
                id: dto.id,
                speakerFullName: dto.speakerFullName,
                speakerFunction: dto.speakerFunction,
                text: dto.text,
                meetingDate: dto.meetingDate,
                parlGroupAbbreviation: dto.parlGroupAbbreviation,
                cantonAbbreviation: dto.cantonAbbreviation,
                councilName: dto.councilName,
                sortOrder: dto.sortOrder,
                type: dto.type,
                startTime: dto.startTime,
                endTime: dto.endTime,
                geschaeft: dto.geschaeftID.flatMap { geschaeftLookup[$0] },
                parlamentarier: dto.parlamentarierPersonNumber.flatMap { parlamentarierLookup[$0] }
            )
            modelContext.insert(wortmeldung)
            if index % 500 == 0 { try modelContext.save() }
        }
        try modelContext.save()

        // Step 6: Import Abstimmungen (→ Geschaeft)
        phase = .importing(step: "Abstimmungen importieren (\(container.abstimmungen.count))…")
        var abstimmungLookup: [Int: Abstimmung] = [:]
        for dto in container.abstimmungen {
            let abstimmung = Abstimmung(
                id: dto.id,
                businessNumber: dto.businessNumber,
                businessShortNumber: dto.businessShortNumber,
                billTitle: dto.billTitle,
                subject: dto.subject,
                meaningYes: dto.meaningYes,
                meaningNo: dto.meaningNo,
                voteEnd: dto.voteEnd,
                idSession: dto.idSession,
                geschaeft: dto.geschaeftID.flatMap { geschaeftLookup[$0] }
            )
            modelContext.insert(abstimmung)
            abstimmungLookup[dto.id] = abstimmung
        }
        try modelContext.save()

        // Step 7: Import Stimmabgaben (→ Abstimmung, Parlamentarier)
        phase = .importing(step: "Stimmabgaben importieren (\(container.stimmabgaben.count))…")
        for (index, dto) in container.stimmabgaben.enumerated() {
            let stimmabgabe = Stimmabgabe(
                id: dto.id,
                personNumber: dto.personNumber,
                decision: dto.decision,
                decisionText: dto.decisionText,
                abstimmung: dto.abstimmungID.flatMap { abstimmungLookup[$0] },
                parlamentarier: dto.parlamentarierPersonNumber.flatMap { parlamentarierLookup[$0] }
            )
            modelContext.insert(stimmabgabe)
            if index % 1000 == 0 { try modelContext.save() }
        }
        try modelContext.save()

        // Step 8: Import PersonInterests (→ Parlamentarier)
        phase = .importing(step: "Interessen importieren (\(container.personInterests.count))…")
        for dto in container.personInterests {
            let interest = PersonInterest(
                personNumber: dto.personNumber,
                interestName: dto.interestName,
                interestTypeText: dto.interestTypeText,
                functionInAgencyText: dto.functionInAgencyText,
                paid: dto.paid,
                organizationTypeText: dto.organizationTypeText,
                parlamentarier: dto.parlamentarierPersonNumber.flatMap { parlamentarierLookup[$0] }
            )
            modelContext.insert(interest)
        }
        try modelContext.save()

        // Step 9: Import PersonOccupations (→ Parlamentarier)
        phase = .importing(step: "Berufe importieren (\(container.personOccupations.count))…")
        for dto in container.personOccupations {
            let occupation = PersonOccupation(
                personNumber: dto.personNumber,
                occupationName: dto.occupationName,
                employer: dto.employer,
                jobTitle: dto.jobTitle,
                parlamentarier: dto.parlamentarierPersonNumber.flatMap { parlamentarierLookup[$0] }
            )
            modelContext.insert(occupation)
        }
        try modelContext.save()

        let counts = """
        \(container.sessions.count) Sessionen, \(container.geschaefte.count) Geschäfte, \
        \(container.parlamentarier.count) Parlamentarier, \(container.wortmeldungen.count) Wortmeldungen, \
        \(container.abstimmungen.count) Abstimmungen, \(container.stimmabgaben.count) Stimmabgaben, \
        \(container.personInterests.count) Interessen, \(container.personOccupations.count) Berufe
        """
        phase = .completed(message: "Import abgeschlossen: \(counts)")
    }

    func reset() {
        phase = .idle
    }
}
