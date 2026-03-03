import SwiftUI
import SwiftData

@main
struct PolitikApp: App {
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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If schema migration fails (e.g. old Item model), delete and recreate
            let url = modelConfiguration.url
            try? FileManager.default.removeItem(at: url)
            // Also remove WAL/SHM files
            try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            TabView {
                SessionListView()
                    .tabItem {
                        Label("Sessionen", systemImage: "building.columns")
                    }
                ParlamentarierListView()
                    .tabItem {
                        Label("Parlamentarier", systemImage: "person.3")
                    }
                WortmeldungListView()
                    .tabItem {
                        Label("Wortmeldungen", systemImage: "text.quote")
                    }
                DataManagementView()
                    .tabItem {
                        Label("Daten", systemImage: "externaldrive")
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
