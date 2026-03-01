import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            SessionListView()
                .tabItem {
                    Label("Sessionen", systemImage: "building.columns")
                }
            ParlamentarierListView()
                .tabItem {
                    Label("Parlamentarier", systemImage: "person.3")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Session.self, Geschaeft.self, Parlamentarier.self, Wortmeldung.self], inMemory: true)
}
