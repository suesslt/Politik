import Foundation
import Vapor
import Fluent

final class SessionSyncService: Sendable {
    let parlamentService: ParlamentService
    let logger: Logger

    init(parlamentService: ParlamentService, logger: Logger) {
        self.parlamentService = parlamentService
        self.logger = logger
    }

    struct SyncResult: Content {
        var sessionsProcessed: Int = 0
        var geschaefteProcessed: Int = 0
        var geschaefteUpdated: Int = 0
        var geschaefteSkipped: Int = 0
        var wortmeldungenCreated: Int = 0
        var abstimmungenCreated: Int = 0
        var stimmabgabenCreated: Int = 0
        var errorsEncountered: Int = 0
        var errors: [String] = []
    }

    // MARK: - Public: Sync Sessions

    func syncSessions(_ sessions: [Session], on db: Database) async throws -> SyncResult {
        var result = SyncResult()

        // Phase 0: Ensure all Parlamentarier are loaded
        var lookup = try await ensureParlamentarierLoaded(on: db)
        logger.info("Parlamentarier loaded: \(lookup.count)")

        // Phase 1+2: Process each session
        for session in sessions {
            logger.info("Syncing session: \(session.sessionName)")
            do {
                let sessionResult = try await syncSession(session, parlamentarierLookup: &lookup, on: db)
                result.geschaefteProcessed += sessionResult.geschaefteProcessed
                result.geschaefteUpdated += sessionResult.geschaefteUpdated
                result.geschaefteSkipped += sessionResult.geschaefteSkipped
                result.wortmeldungenCreated += sessionResult.wortmeldungenCreated
                result.abstimmungenCreated += sessionResult.abstimmungenCreated
                result.stimmabgabenCreated += sessionResult.stimmabgabenCreated
                result.errorsEncountered += sessionResult.errorsEncountered
                result.errors.append(contentsOf: sessionResult.errors)

                session.isSynced = true
                session.lastSyncDate = Date()
                try await session.save(on: db)
                result.sessionsProcessed += 1
            } catch {
                let errorDetail = String(reflecting: error)
                logger.error("Session sync failed for '\(session.sessionName)': \(errorDetail)")
                result.errorsEncountered += 1
                result.errors.append("Session \(session.sessionName): \(errorDetail)")
            }
        }

        return result
    }

    // MARK: - Public: Sync Geschaefte Details

    func syncGeschaefteDetails(_ geschaefte: [Geschaeft], on db: Database) async throws -> SyncResult {
        var result = SyncResult()
        var lookup = try await ensureParlamentarierLoaded(on: db)

        for geschaeft in geschaefte {
            do {
                let subResult = try await syncGeschaeft(geschaeft, forceReloadTranscripts: false, parlamentarierLookup: &lookup, on: db)
                result.wortmeldungenCreated += subResult.wortmeldungenCreated
                result.geschaefteProcessed += 1
            } catch {
                result.errorsEncountered += 1
                result.errors.append("Geschäft \(geschaeft.businessShortNumber): \(error.localizedDescription)")
            }
        }
        return result
    }

    // MARK: - Private: Parlamentarier

    private func ensureParlamentarierLoaded(on db: Database) async throws -> [Int: Parlamentarier] {
        let dtos = try await parlamentService.fetchAllParlamentarier()
        let existing = try await Parlamentarier.query(on: db).all()
        var lookup = Dictionary(uniqueKeysWithValues: existing.compactMap { p -> (Int, Parlamentarier)? in
            guard let id = p.id else { return nil }
            return (id, p)
        })

        for dto in dtos {
            let personNumber = dto.PersonNumber ?? dto.ID ?? 0
            guard personNumber != 0, lookup[personNumber] == nil else { continue }
            let person = Parlamentarier(
                personNumber: personNumber,
                firstName: dto.FirstName ?? "",
                lastName: dto.LastName ?? "",
                partyAbbreviation: dto.PartyAbbreviation,
                parlGroupAbbreviation: dto.ParlGroupAbbreviation,
                cantonAbbreviation: dto.CantonAbbreviation,
                councilName: dto.CouncilName,
                councilAbbreviation: dto.CouncilAbbreviation,
                isActive: dto.Active ?? true
            )
            try await person.save(on: db)
            lookup[personNumber] = person
        }

        // Enrich Parlamentarier without details (occupations, interests, detail fields)
        let needsDetail = lookup.values.filter { !$0.isDetailLoaded }
        logger.info("Parlamentarier needing detail enrichment: \(needsDetail.count)")

        for person in needsDetail {
            guard let pn = person.id else { continue }
            do {
                try await enrichParlamentarier(person, personNumber: pn, on: db)
            } catch {
                logger.warning("Failed to enrich Parlamentarier \(pn): \(error)")
            }
        }

        return lookup
    }

    private func enrichParlamentarier(_ person: Parlamentarier, personNumber: Int, on db: Database) async throws {
        // Load detail fields
        if let detail = try await parlamentService.fetchParlamentarierDetail(personNumber: personNumber) {
            person.partyName = detail.PartyName
            person.parlGroupName = detail.ParlGroupName
            person.cantonName = detail.CantonName
            person.nationality = detail.Nationality
            person.dateOfBirth = ODataDateParser.parse(detail.DateOfBirth)
            person.birthPlaceCity = detail.BirthPlace_City
            person.birthPlaceCanton = detail.BirthPlace_Canton
            person.citizenship = detail.Citizenship
            person.maritalStatusText = detail.MaritalStatusText
            person.numberOfChildren = detail.NumberOfChildren
            person.dateJoining = ODataDateParser.parse(detail.DateJoining)
            person.dateLeaving = ODataDateParser.parse(detail.DateLeaving)
            person.dateElection = ODataDateParser.parse(detail.DateElection)
            person.militaryRankText = detail.MilitaryRankText
        }

        // Load occupations
        let occupationDTOs = try await parlamentService.fetchPersonOccupations(personNumber: personNumber)
        for dto in occupationDTOs {
            let occ = PersonOccupation(
                personNumber: personNumber,
                occupationName: dto.OccupationName ?? "",
                employer: dto.Employer,
                jobTitle: dto.JobTitle
            )
            occ.$parlamentarier.id = personNumber
            try await occ.save(on: db)
        }

        // Load interests
        let interestDTOs = try await parlamentService.fetchPersonInterests(personNumber: personNumber)
        for dto in interestDTOs {
            let interest = PersonInterest(
                personNumber: personNumber,
                interestName: dto.InterestName ?? "",
                interestTypeText: dto.InterestTypeText,
                functionInAgencyText: dto.FunctionInAgencyText,
                paid: dto.Paid,
                organizationTypeText: dto.OrganizationTypeText
            )
            interest.$parlamentarier.id = personNumber
            try await interest.save(on: db)
        }

        person.isDetailLoaded = true
        try await person.save(on: db)
        logger.info("Enriched: \(person.fullName) (\(occupationDTOs.count) occupations, \(interestDTOs.count) interests)")
    }

    // MARK: - Private: Session Sync

    private func syncSession(_ session: Session, parlamentarierLookup: inout [Int: Parlamentarier], on db: Database) async throws -> SyncResult {
        var result = SyncResult()
        let lastSync = session.lastSyncDate
        let isIncremental = lastSync != nil

        // Fetch Geschaefte
        let geschaefteDTOs: [GeschaeftDTO]
        if let lastSync {
            geschaefteDTOs = try await parlamentService.fetchGeschaefteModifiedSince(sessionID: session.id!, since: lastSync)
        } else {
            geschaefteDTOs = try await parlamentService.fetchGeschaefte(sessionID: session.id!)
        }

        // Load existing Geschaefte for this session
        try await session.$geschaefte.load(on: db)
        let existingLookup = Dictionary(uniqueKeysWithValues: session.geschaefte.compactMap { g -> (Int, Geschaeft)? in
            guard let id = g.id else { return nil }
            return (id, g)
        })
        var modifiedGeschaeftIDs: Set<Int> = []

        for dto in geschaefteDTOs {
            if let existing = existingLookup[dto.ID] {
                // Already in this session – update fields
                existing.title = dto.Title ?? existing.title
                existing.businessStatusText = dto.BusinessStatusText ?? existing.businessStatusText
                existing.businessStatusDate = ODataDateParser.parse(dto.BusinessStatusDate) ?? existing.businessStatusDate
                existing.descriptionText = dto.Description ?? existing.descriptionText
                existing.tagNames = dto.TagNames ?? existing.tagNames
                try await existing.save(on: db)
                modifiedGeschaeftIDs.insert(dto.ID)
                result.geschaefteUpdated += 1
            } else if let existingInDB = try await Geschaeft.find(dto.ID, on: db) {
                // Exists in DB from another session – update and re-assign
                existingInDB.title = dto.Title ?? existingInDB.title
                existingInDB.businessStatusText = dto.BusinessStatusText ?? existingInDB.businessStatusText
                existingInDB.businessStatusDate = ODataDateParser.parse(dto.BusinessStatusDate) ?? existingInDB.businessStatusDate
                existingInDB.descriptionText = dto.Description ?? existingInDB.descriptionText
                existingInDB.tagNames = dto.TagNames ?? existingInDB.tagNames
                existingInDB.$session.id = session.id
                try await existingInDB.save(on: db)
                modifiedGeschaeftIDs.insert(dto.ID)
                result.geschaefteUpdated += 1
            } else {
                // New – insert
                let geschaeft = Geschaeft(
                    id: dto.ID,
                    businessShortNumber: dto.BusinessShortNumber ?? "",
                    title: dto.Title ?? "",
                    businessTypeName: dto.BusinessTypeName ?? "",
                    businessTypeAbbreviation: dto.BusinessTypeAbbreviation ?? "",
                    businessStatusText: dto.BusinessStatusText ?? "",
                    businessStatusDate: ODataDateParser.parse(dto.BusinessStatusDate),
                    submissionDate: ODataDateParser.parse(dto.SubmissionDate),
                    submittedBy: dto.SubmittedBy,
                    descriptionText: dto.Description,
                    submissionCouncilName: dto.SubmissionCouncilName,
                    responsibleDepartmentName: dto.ResponsibleDepartmentName,
                    responsibleDepartmentAbbreviation: dto.ResponsibleDepartmentAbbreviation,
                    tagNames: dto.TagNames
                )
                geschaeft.$session.id = session.id
                try await geschaeft.save(on: db)
                modifiedGeschaeftIDs.insert(dto.ID)
            }
        }

        // Reload session geschaefte
        try await session.$geschaefte.load(on: db)

        // Process Geschaefte (Urheber + Transcripts)
        let geschaefteToProcess: [Geschaeft]
        if isIncremental {
            geschaefteToProcess = session.geschaefte.filter { g in
                guard let id = g.id else { return false }
                return modifiedGeschaeftIDs.contains(id) || g.wortmeldungen.isEmpty
            }
            result.geschaefteSkipped = session.geschaefte.count - geschaefteToProcess.count
        } else {
            geschaefteToProcess = session.geschaefte
        }

        for geschaeft in geschaefteToProcess {
            do {
                let subResult = try await syncGeschaeft(
                    geschaeft,
                    forceReloadTranscripts: geschaeft.id.map { modifiedGeschaeftIDs.contains($0) } ?? false,
                    parlamentarierLookup: &parlamentarierLookup,
                    on: db
                )
                result.wortmeldungenCreated += subResult.wortmeldungenCreated
                result.geschaefteProcessed += 1
            } catch {
                result.errorsEncountered += 1
                result.errors.append("Geschäft \(geschaeft.businessShortNumber): \(error.localizedDescription)")
            }
        }

        // Sync Abstimmungen
        let voteResult = try await syncAbstimmungen(for: session, lastSync: lastSync, parlamentarierLookup: parlamentarierLookup, on: db)
        result.abstimmungenCreated += voteResult.abstimmungenCreated
        result.stimmabgabenCreated += voteResult.stimmabgabenCreated
        result.errorsEncountered += voteResult.errorsEncountered
        result.errors.append(contentsOf: voteResult.errors)

        return result
    }

    // MARK: - Private: Geschaeft Sync

    private func syncGeschaeft(_ geschaeft: Geschaeft, forceReloadTranscripts: Bool, parlamentarierLookup: inout [Int: Parlamentarier], on db: Database) async throws -> SyncResult {
        var result = SyncResult()

        if geschaeft.$urheber.id == nil {
            try await loadUrheber(for: geschaeft, parlamentarierLookup: &parlamentarierLookup, on: db)
        }

        try await geschaeft.$wortmeldungen.load(on: db)
        let hasSpeeches = geschaeft.wortmeldungen.contains { $0.isRede }
        if !hasSpeeches || forceReloadTranscripts {
            let created = try await loadTranscripts(for: geschaeft, parlamentarierLookup: parlamentarierLookup, on: db)
            result.wortmeldungenCreated = created
        }

        return result
    }

    // MARK: - Private: Urheber

    private func loadUrheber(for geschaeft: Geschaeft, parlamentarierLookup: inout [Int: Parlamentarier], on db: Database) async throws {
        guard let geschaeftId = geschaeft.id,
              let roleDTO = try await parlamentService.fetchUrheber(businessID: geschaeftId),
              let memberNumber = roleDTO.MemberCouncilNumber else { return }

        if let existing = parlamentarierLookup[memberNumber] {
            geschaeft.$urheber.id = existing.id
        } else if let dto = try await parlamentService.fetchParlamentarier(personNumber: memberNumber) {
            let personNumber = dto.PersonNumber ?? memberNumber
            let person = Parlamentarier(
                personNumber: personNumber,
                firstName: dto.FirstName ?? "",
                lastName: dto.LastName ?? "",
                partyAbbreviation: dto.PartyAbbreviation,
                parlGroupAbbreviation: dto.ParlGroupAbbreviation,
                cantonAbbreviation: dto.CantonAbbreviation,
                councilName: dto.CouncilName,
                councilAbbreviation: dto.CouncilAbbreviation,
                isActive: dto.Active ?? false
            )
            try await person.save(on: db)
            parlamentarierLookup[personNumber] = person
            geschaeft.$urheber.id = person.id
        }
        try await geschaeft.save(on: db)
    }

    // MARK: - Private: Transcripts

    private func loadTranscripts(for geschaeft: Geschaeft, parlamentarierLookup: [Int: Parlamentarier], on db: Database) async throws -> Int {
        guard let geschaeftId = geschaeft.id else { return 0 }

        let subjects = try await parlamentService.fetchSubjectBusinesses(businessID: geschaeftId)
        let existingIDs = Set(geschaeft.wortmeldungen.map { $0.id ?? "" })
        var created = 0

        for subject in subjects {
            guard let idSubject = subject.IdSubject else { continue }
            let transcripts = try await parlamentService.fetchTranscriptsForSubject(idSubject: idSubject)

            for dto in transcripts {
                guard let dtoID = dto.ID, !existingIDs.contains(dtoID) else { continue }
                let wortmeldung = Wortmeldung(
                    id: dtoID,
                    speakerFullName: dto.SpeakerFullName ?? "",
                    speakerFunction: dto.SpeakerFunction,
                    text: dto.Text ?? "",
                    meetingDate: dto.MeetingDate,
                    parlGroupAbbreviation: dto.ParlGroupAbbreviation,
                    cantonAbbreviation: dto.CantonAbbreviation,
                    councilName: dto.CouncilName,
                    sortOrder: dto.SortOrder ?? 0,
                    type: dto.TranscriptType ?? 0,
                    startTime: ODataDateParser.parse(dto.Start),
                    endTime: ODataDateParser.parse(dto.End)
                )
                wortmeldung.$geschaeft.id = geschaeft.id
                if let pn = dto.PersonNumber {
                    wortmeldung.$parlamentarier.id = parlamentarierLookup[pn]?.id
                }
                try await wortmeldung.save(on: db)
                created += 1
            }
        }
        return created
    }

    // MARK: - Private: Abstimmungen Sync

    private func syncAbstimmungen(for session: Session, lastSync: Date?, parlamentarierLookup: [Int: Parlamentarier], on db: Database) async throws -> SyncResult {
        var result = SyncResult()
        guard let sessionId = session.id else { return result }

        let voteDTOs: [VoteDTO]
        if let lastSync {
            voteDTOs = try await parlamentService.fetchVotesModifiedSince(sessionID: sessionId, since: lastSync)
        } else {
            voteDTOs = try await parlamentService.fetchVotes(sessionID: sessionId)
        }

        logger.info("Fetched \(voteDTOs.count) vote DTOs for session \(session.sessionName)")

        // Build Geschaeft lookup – only for this session's Geschaefte
        try await session.$geschaefte.load(on: db)
        var geschaeftLookup = Dictionary(uniqueKeysWithValues: session.geschaefte.compactMap { g -> (Int, Geschaeft)? in
            guard let id = g.id else { return nil }
            return (id, g)
        })

        // Fetch missing Geschaefte referenced by votes
        let referencedBusinessNumbers = Set(voteDTOs.compactMap(\.BusinessNumber))
        let missingBusinessNumbers = referencedBusinessNumbers.subtracting(geschaeftLookup.keys)

        for businessID in missingBusinessNumbers {
            do {
                // Check if Geschaeft already exists in DB (from another session)
                if let existingInDB = try await Geschaeft.find(businessID, on: db) {
                    geschaeftLookup[businessID] = existingInDB
                } else if let dto = try await parlamentService.fetchBusiness(id: businessID) {
                    let geschaeft = Geschaeft(
                        id: dto.ID,
                        businessShortNumber: dto.BusinessShortNumber ?? "",
                        title: dto.Title ?? "",
                        businessTypeName: dto.BusinessTypeName ?? "",
                        businessTypeAbbreviation: dto.BusinessTypeAbbreviation ?? "",
                        businessStatusText: dto.BusinessStatusText ?? "",
                        businessStatusDate: ODataDateParser.parse(dto.BusinessStatusDate),
                        submissionDate: ODataDateParser.parse(dto.SubmissionDate),
                        submittedBy: dto.SubmittedBy,
                        descriptionText: dto.Description,
                        submissionCouncilName: dto.SubmissionCouncilName,
                        responsibleDepartmentName: dto.ResponsibleDepartmentName,
                        responsibleDepartmentAbbreviation: dto.ResponsibleDepartmentAbbreviation,
                        tagNames: dto.TagNames
                    )
                    geschaeft.$session.id = session.id
                    try await geschaeft.save(on: db)
                    geschaeftLookup[dto.ID] = geschaeft
                }
            } catch {
                logger.warning("Failed to fetch Geschäft \(businessID): \(error)")
            }
        }

        // Only load existing Abstimmungen for THIS session (not entire DB)
        let sessionAbstimmungen = try await Abstimmung.query(on: db)
            .filter(\.$idSession == sessionId)
            .all()
        let existingIDs = Set(sessionAbstimmungen.compactMap(\.id))

        logger.info("Existing Abstimmungen for session: \(existingIDs.count)")

        // Insert new Abstimmungen
        var newAbstimmungen: [Abstimmung] = []
        for dto in voteDTOs {
            guard !existingIDs.contains(dto.ID) else { continue }
            let abstimmung = Abstimmung(
                id: dto.ID,
                businessNumber: dto.BusinessNumber,
                businessShortNumber: dto.BusinessShortNumber,
                billTitle: dto.BillTitle,
                subject: dto.Subject,
                meaningYes: dto.MeaningYes,
                meaningNo: dto.MeaningNo,
                voteEnd: ODataDateParser.parse(dto.VoteEnd),
                idSession: dto.IdSession
            )
            if let bn = dto.BusinessNumber {
                abstimmung.$geschaeft.id = geschaeftLookup[bn]?.id
            }
            try await abstimmung.save(on: db)
            newAbstimmungen.append(abstimmung)
            result.abstimmungenCreated += 1
        }

        // Only fetch voting records for Abstimmungen that don't have Stimmabgaben yet
        // Check only this session's existing Abstimmungen (not the entire DB)
        var abstimmungenNeedingVotings: [Abstimmung] = newAbstimmungen
        for abstimmung in sessionAbstimmungen {
            let count = try await Stimmabgabe.query(on: db)
                .filter(\.$abstimmung.$id == abstimmung.id)
                .count()
            if count == 0 {
                abstimmungenNeedingVotings.append(abstimmung)
            }
        }

        logger.info("Abstimmungen needing voting records: \(abstimmungenNeedingVotings.count)")

        for (index, abstimmung) in abstimmungenNeedingVotings.enumerated() {
            guard let abstimmungId = abstimmung.id else { continue }
            do {
                // Check existing Stimmabgaben only for this Abstimmung
                let existingStimmabgabeIDs = try await Stimmabgabe.query(on: db)
                    .filter(\.$abstimmung.$id == abstimmungId)
                    .all()
                    .compactMap(\.id)
                let existingSet = Set(existingStimmabgabeIDs)

                let votingDTOs = try await parlamentService.fetchVotings(voteID: abstimmungId)
                for vdto in votingDTOs {
                    guard !existingSet.contains(vdto.ID) else { continue }
                    let stimmabgabe = Stimmabgabe(
                        id: vdto.ID,
                        personNumber: vdto.PersonNumber ?? 0,
                        decision: vdto.Decision ?? 0,
                        decisionText: vdto.DecisionText
                    )
                    stimmabgabe.$abstimmung.id = abstimmung.id
                    if let pn = vdto.PersonNumber {
                        stimmabgabe.$parlamentarier.id = parlamentarierLookup[pn]?.id
                    }
                    try await stimmabgabe.save(on: db)
                    result.stimmabgabenCreated += 1
                }
            } catch {
                result.errorsEncountered += 1
                result.errors.append("Abstimmung \(abstimmungId): \(error.localizedDescription)")
            }

            if (index + 1) % 10 == 0 || index == abstimmungenNeedingVotings.count - 1 {
                logger.info("Abstimmungen progress: \(index + 1)/\(abstimmungenNeedingVotings.count)")
            }
        }

        return result
    }
}
