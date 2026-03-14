import SwiftUI
import SwiftData

@main
struct ParlamentarierExportApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Session.self,
            Geschaeft.self,
            Parlamentarier.self,
            Wortmeldung.self,
            Abstimmung.self,
            Stimmabgabe.self,
            PersonInterest.self,
            PersonOccupation.self,
            Proposition.self,
            DailyReport.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ExportView()
        }
        .modelContainer(sharedModelContainer)
    }
}
