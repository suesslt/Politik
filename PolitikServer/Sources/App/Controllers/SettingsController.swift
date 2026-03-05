import Vapor

struct SettingsController {
    func index(req: Request) async throws -> View {
        let hasApiKey = !((Environment.get("CLAUDE_API_KEY") ?? "").isEmpty)

        struct Context: Encodable {
            let title: String
            let hasApiKey: Bool
            let dbHost: String
            let dbName: String
        }
        return try await req.view.render("settings/index", Context(
            title: "Einstellungen",
            hasApiKey: hasApiKey,
            dbHost: Environment.get("DB_HOST") ?? "localhost",
            dbName: Environment.get("DB_NAME") ?? "politik"
        ))
    }
}
