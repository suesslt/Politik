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
                result.errorsEncountered += 1
                result.errors.append("Session \(session.sessionName): \(error.localizedDescription)")
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
        return lookup
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
                existing.title = dto.Title ?? existing.title
                existing.businessStatusText = dto.BusinessStatusText ?? existing.businessStatusText
                existing.businessStatusDate = ODataDateParser.parse(dto.BusinessStatusDate) ?? existing.businessStatusDate
                existing.descriptionText = dto.Description ?? existing.descriptionText
                existing.tagNames = dto.TagNames ?? existing.tagNames
                try await existing.save(on: db)
                modifiedGeschaeftIDs.insert(dto.ID)
                result.geschaefteUpdated += 1
            } else {
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

        let voteDTOs: [VoteDTO]
        if let lastSync {
            voteDTOs = try await parlamentService.fetchVotesModifiedSince(sessionID: session.id!, since: lastSync)
        } else {
            voteDTOs = try await parlamentService.fetchVotes(sessionID: session.id!)
        }

        // Build Geschaeft lookup
        let allGeschaefte = try await Geschaeft.query(on: db).all()
        var geschaeftLookup = Dictionary(uniqueKeysWithValues: allGeschaefte.compactMap { g -> (Int, Geschaeft)? in
            guard let id = g.id else { return nil }
            return (id, g)
        })

        // Fetch missing Geschaefte
        let referencedBusinessNumbers = Set(voteDTOs.compactMap(\.BusinessNumber))
        let missingBusinessNumbers = referencedBusinessNumbers.subtracting(geschaeftLookup.keys)

        for businessID in missingBusinessNumbers {
            do {
                if let dto = try await parlamentService.fetchBusiness(id: businessID) {
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
                // Skip
            }
        }

        // Check existing Abstimmungen
        let existingAbstimmungen = try await Abstimmung.query(on: db).all()
        let existingIDs = Set(existingAbstimmungen.compactMap(\.id))

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

        // Fetch Voting records for new and incomplete Abstimmungen
        let incompleteAbstimmungen = existingAbstimmungen.filter { abstimmung in
            // Check if has stimmabgaben - we'll load them
            true // We'll filter after loading
        }

        for abstimmung in incompleteAbstimmungen {
            try await abstimmung.$stimmabgaben.load(on: db)
        }

        let abstimmungenNeedingVotings = incompleteAbstimmungen.filter { $0.stimmabgaben.isEmpty } + newAbstimmungen
        let existingStimmabgaben = try await Stimmabgabe.query(on: db).all()
        let existingStimmabgabeIDs = Set(existingStimmabgaben.compactMap(\.id))

        for (index, abstimmung) in abstimmungenNeedingVotings.enumerated() {
            guard let abstimmungId = abstimmung.id else { continue }
            do {
                let votingDTOs = try await parlamentService.fetchVotings(voteID: abstimmungId)
                for vdto in votingDTOs {
                    guard !existingStimmabgabeIDs.contains(vdto.ID) else { continue }
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

            if index % 10 == 0 {
                logger.info("Abstimmungen: \(index + 1)/\(abstimmungenNeedingVotings.count)")
            }
        }

        return result
    }
}
