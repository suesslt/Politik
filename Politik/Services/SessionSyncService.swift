import Foundation
import SwiftData

@MainActor @Observable
final class SessionSyncService {

    // MARK: - Types

    enum SyncPhase: Equatable {
        case idle
        case preparingParlamentarier
        case syncingSession(name: String, index: Int, total: Int)
        case syncingGeschaeft(title: String, current: Int, total: Int)
        case syncingAbstimmungen(current: Int, total: Int)
        case completed
        case cancelled
    }

    struct SyncStats: Equatable {
        var sessionsProcessed = 0
        var geschaefteProcessed = 0
        var geschaefteUpdated = 0
        var geschaefteSkipped = 0
        var wortmeldungenCreated = 0
        var abstimmungenCreated = 0
        var stimmabgabenCreated = 0
        var errorsEncountered = 0
        var isIncremental = false
    }

    struct SyncError: Identifiable {
        let id = UUID()
        let geschaeftID: Int
        let geschaeftTitle: String
        let message: String
    }

    // MARK: - Observable State

    private(set) var phase: SyncPhase = .idle
    private(set) var isSyncing = false
    private(set) var stats = SyncStats()
    private(set) var errors: [SyncError] = []

    private let service = ParlamentService()

    // MARK: - Public API

    func syncSessions(_ sessions: [Session], modelContext: ModelContext) async {
        isSyncing = true
        phase = .preparingParlamentarier
        stats = SyncStats()
        errors = []

        do {
            // Phase 0: Ensure all Parlamentarier are loaded, build lookup
            var lookup = try await ensureParlamentarierLoaded(modelContext: modelContext)

            // Phase 1+2: Process each session
            for (index, session) in sessions.enumerated() {
                try Task.checkCancellation()
                phase = .syncingSession(name: session.sessionName, index: index + 1, total: sessions.count)

                let isIncremental = session.lastSyncDate != nil
                stats.isIncremental = isIncremental

                try await syncSession(session, parlamentarierLookup: &lookup, modelContext: modelContext)

                session.isSynced = true
                session.lastSyncDate = Date()
                try modelContext.save()
                stats.sessionsProcessed += 1
            }

            phase = .completed
        } catch is CancellationError {
            phase = .cancelled
        } catch {
            phase = .completed
        }

        isSyncing = false
    }

    func reset() {
        phase = .idle
        stats = SyncStats()
        errors = []
    }

    // MARK: - Phase 0: Parlamentarier

    private func ensureParlamentarierLoaded(modelContext: ModelContext) async throws -> [Int: Parlamentarier] {
        let dtos = try await service.fetchAllParlamentarier()

        let descriptor = FetchDescriptor<Parlamentarier>()
        let existing = try modelContext.fetch(descriptor)
        var lookup = Dictionary(uniqueKeysWithValues: existing.map { ($0.personNumber, $0) })

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
            modelContext.insert(person)
            lookup[personNumber] = person
        }
        try modelContext.save()

        return lookup
    }

    // MARK: - Session Sync

    private func syncSession(_ session: Session, parlamentarierLookup: inout [Int: Parlamentarier], modelContext: ModelContext) async throws {
        let lastSync = session.lastSyncDate
        let isIncremental = lastSync != nil

        // Fetch Geschaefte – incremental if possible
        let geschaefteDTOs: [GeschaeftDTO]
        if let lastSync {
            geschaefteDTOs = try await service.fetchGeschaefteModifiedSince(sessionID: session.id, since: lastSync)
        } else {
            geschaefteDTOs = try await service.fetchGeschaefte(sessionID: session.id)
        }

        let existingLookup = Dictionary(uniqueKeysWithValues: session.geschaefte.map { ($0.id, $0) })
        var modifiedGeschaeftIDs: Set<Int> = []

        for dto in geschaefteDTOs {
            if let existing = existingLookup[dto.ID] {
                // Update existing Geschaeft with latest data
                existing.title = dto.Title ?? existing.title
                existing.businessStatusText = dto.BusinessStatusText ?? existing.businessStatusText
                existing.businessStatusDate = ODataDateParser.parse(dto.BusinessStatusDate) ?? existing.businessStatusDate
                existing.descriptionText = dto.Description ?? existing.descriptionText
                existing.tagNames = dto.TagNames ?? existing.tagNames
                modifiedGeschaeftIDs.insert(dto.ID)
                stats.geschaefteUpdated += 1
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
                    tagNames: dto.TagNames,
                    session: session
                )
                modelContext.insert(geschaeft)
                modifiedGeschaeftIDs.insert(dto.ID)
            }
        }
        try modelContext.save()

        // Process Geschaefte (Urheber + Transcripts)
        // In incremental mode: only process new/modified Geschaefte
        let geschaefteToProcess: [Geschaeft]
        if isIncremental {
            geschaefteToProcess = session.geschaefte.filter { modifiedGeschaeftIDs.contains($0.id) || !$0.wortmeldungen.contains(where: \.isRede) }
            stats.geschaefteSkipped = session.geschaefte.count - geschaefteToProcess.count
        } else {
            geschaefteToProcess = session.geschaefte
        }

        let total = geschaefteToProcess.count
        for (index, geschaeft) in geschaefteToProcess.enumerated() {
            try Task.checkCancellation()
            phase = .syncingGeschaeft(title: geschaeft.businessShortNumber, current: index + 1, total: total)

            do {
                try await syncGeschaeft(geschaeft, forceReloadTranscripts: modifiedGeschaeftIDs.contains(geschaeft.id), parlamentarierLookup: &parlamentarierLookup, modelContext: modelContext)
                stats.geschaefteProcessed += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                errors.append(SyncError(
                    geschaeftID: geschaeft.id,
                    geschaeftTitle: geschaeft.title,
                    message: error.localizedDescription
                ))
                stats.errorsEncountered += 1
            }
        }

        // Sync Abstimmungen for this session
        try await syncAbstimmungen(for: session, lastSync: lastSync, parlamentarierLookup: parlamentarierLookup, modelContext: modelContext)
    }

    // MARK: - Geschaeft Sync

    private func syncGeschaeft(_ geschaeft: Geschaeft, forceReloadTranscripts: Bool, parlamentarierLookup: inout [Int: Parlamentarier], modelContext: ModelContext) async throws {
        if geschaeft.urheber == nil {
            try await loadUrheber(for: geschaeft, parlamentarierLookup: &parlamentarierLookup, modelContext: modelContext)
        }

        let hasSpeeches = geschaeft.wortmeldungen.contains { $0.isRede }
        if !hasSpeeches || forceReloadTranscripts {
            try await loadTranscripts(for: geschaeft, parlamentarierLookup: parlamentarierLookup, modelContext: modelContext)
        }

        try modelContext.save()
    }

    // MARK: - Urheber

    private func loadUrheber(for geschaeft: Geschaeft, parlamentarierLookup: inout [Int: Parlamentarier], modelContext: ModelContext) async throws {
        guard let roleDTO = try await service.fetchUrheber(businessID: geschaeft.id),
              let memberNumber = roleDTO.MemberCouncilNumber else { return }

        if let existing = parlamentarierLookup[memberNumber] {
            geschaeft.urheber = existing
        } else if let dto = try await service.fetchParlamentarier(personNumber: memberNumber) {
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
            modelContext.insert(person)
            parlamentarierLookup[personNumber] = person
            geschaeft.urheber = person
        }
    }

    // MARK: - Transcripts (parallel per subject)

    private func loadTranscripts(for geschaeft: Geschaeft, parlamentarierLookup: [Int: Parlamentarier], modelContext: ModelContext) async throws {
        let oldNonSpeech = geschaeft.wortmeldungen.filter { !$0.isRede }
        for old in oldNonSpeech {
            modelContext.delete(old)
        }

        let subjects = try await service.fetchSubjectBusinesses(businessID: geschaeft.id)
        let existingIDs = Set(geschaeft.wortmeldungen.map(\.id))

        try await withThrowingTaskGroup(of: [TranscriptDTO].self) { group in
            let maxConcurrency = 5
            var iterator = subjects.makeIterator()

            for _ in 0..<maxConcurrency {
                guard let subject = iterator.next(), let idSubject = subject.IdSubject else { break }
                group.addTask { [service] in
                    try await service.fetchTranscriptsForSubject(idSubject: idSubject)
                }
            }

            for try await transcripts in group {
                for dto in transcripts {
                    guard let dtoID = dto.ID, !existingIDs.contains(dtoID) else { continue }
                    let parlamentarier: Parlamentarier? = if let pn = dto.PersonNumber {
                        parlamentarierLookup[pn]
                    } else {
                        nil
                    }
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
                        endTime: ODataDateParser.parse(dto.End),
                        geschaeft: geschaeft,
                        parlamentarier: parlamentarier
                    )
                    modelContext.insert(wortmeldung)
                    stats.wortmeldungenCreated += 1
                }

                if let subject = iterator.next(), let idSubject = subject.IdSubject {
                    group.addTask { [service] in
                        try await service.fetchTranscriptsForSubject(idSubject: idSubject)
                    }
                }
            }
        }
    }

    // MARK: - Abstimmungen Sync

    private func syncAbstimmungen(for session: Session, lastSync: Date?, parlamentarierLookup: [Int: Parlamentarier], modelContext: ModelContext) async throws {
        // Fetch Votes – incremental if possible
        let voteDTOs: [VoteDTO]
        if let lastSync {
            voteDTOs = try await service.fetchVotesModifiedSince(sessionID: session.id, since: lastSync)
        } else {
            voteDTOs = try await service.fetchVotes(sessionID: session.id)
        }

        // Build Geschaeft lookup by ID for linking
        let geschaeftDescriptor = FetchDescriptor<Geschaeft>()
        let allGeschaefte = try modelContext.fetch(geschaeftDescriptor)
        var geschaeftLookup = Dictionary(uniqueKeysWithValues: allGeschaefte.map { ($0.id, $0) })

        // Find BusinessNumbers that are referenced by Votes but don't exist locally
        let referencedBusinessNumbers = Set(voteDTOs.compactMap(\.BusinessNumber))
        let missingBusinessNumbers = referencedBusinessNumbers.subtracting(geschaeftLookup.keys)

        // Fetch missing Geschaefte from API
        for businessID in missingBusinessNumbers {
            try Task.checkCancellation()
            do {
                if let dto = try await service.fetchBusiness(id: businessID) {
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
                        tagNames: dto.TagNames,
                        session: session
                    )
                    modelContext.insert(geschaeft)
                    geschaeftLookup[dto.ID] = geschaeft
                }
            } catch {
                // Skip missing business, Abstimmung will be created without link
            }
        }
        if !missingBusinessNumbers.isEmpty {
            try modelContext.save()
        }

        // Check existing Abstimmungen
        let abstimmungDescriptor = FetchDescriptor<Abstimmung>()
        let existingAbstimmungen = try modelContext.fetch(abstimmungDescriptor)
        let existingIDs = Set(existingAbstimmungen.map(\.id))

        // Repair existing Abstimmungen that have no Geschaeft link
        for existing in existingAbstimmungen {
            if existing.geschaeft == nil, let bn = existing.businessNumber, let geschaeft = geschaeftLookup[bn] {
                existing.geschaeft = geschaeft
            }
        }

        // Repair existing Stimmabgaben that have no Parlamentarier link
        let stimmabgabeDescriptor = FetchDescriptor<Stimmabgabe>()
        let existingStimmabgaben = try modelContext.fetch(stimmabgabeDescriptor)
        for existing in existingStimmabgaben {
            if existing.parlamentarier == nil {
                existing.parlamentarier = parlamentarierLookup[existing.personNumber]
            }
        }
        try modelContext.save()

        // Insert new Abstimmungen
        var newAbstimmungen: [Abstimmung] = []
        for dto in voteDTOs {
            guard !existingIDs.contains(dto.ID) else { continue }
            let geschaeft = dto.BusinessNumber.flatMap { geschaeftLookup[$0] }
            let abstimmung = Abstimmung(
                id: dto.ID,
                businessNumber: dto.BusinessNumber,
                businessShortNumber: dto.BusinessShortNumber,
                billTitle: dto.BillTitle,
                subject: dto.Subject,
                meaningYes: dto.MeaningYes,
                meaningNo: dto.MeaningNo,
                voteEnd: ODataDateParser.parse(dto.VoteEnd),
                idSession: dto.IdSession,
                geschaeft: geschaeft
            )
            modelContext.insert(abstimmung)
            newAbstimmungen.append(abstimmung)
            stats.abstimmungenCreated += 1
        }
        try modelContext.save()

        // Fetch Voting records for each new Abstimmung
        // Also check existing Abstimmungen that have no Stimmabgaben (incomplete from earlier sync)
        let abstimmungenNeedingVotings = existingAbstimmungen.filter { $0.stimmabgaben.isEmpty } + newAbstimmungen
        let total = abstimmungenNeedingVotings.count
        let existingStimmabgabeIDs = Set(existingStimmabgaben.map(\.id))

        for (index, abstimmung) in abstimmungenNeedingVotings.enumerated() {
            try Task.checkCancellation()
            phase = .syncingAbstimmungen(current: index + 1, total: total)

            do {
                let votingDTOs = try await service.fetchVotings(voteID: abstimmung.id)
                for vdto in votingDTOs {
                    guard !existingStimmabgabeIDs.contains(vdto.ID) else { continue }
                    let parlamentarier = vdto.PersonNumber.flatMap { parlamentarierLookup[$0] }
                    let stimmabgabe = Stimmabgabe(
                        id: vdto.ID,
                        personNumber: vdto.PersonNumber ?? 0,
                        decision: vdto.Decision ?? 0,
                        decisionText: vdto.DecisionText,
                        abstimmung: abstimmung,
                        parlamentarier: parlamentarier
                    )
                    modelContext.insert(stimmabgabe)
                    stats.stimmabgabenCreated += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                errors.append(SyncError(
                    geschaeftID: abstimmung.businessNumber ?? abstimmung.id,
                    geschaeftTitle: "Abstimmung: \(abstimmung.subject ?? "\(abstimmung.id)")",
                    message: error.localizedDescription
                ))
                stats.errorsEncountered += 1
            }

            // Batch save every 10 Abstimmungen
            if index % 10 == 0 {
                try modelContext.save()
            }
        }
        try modelContext.save()
    }
}
