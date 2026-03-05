import Vapor
import Fluent
import FluentPostgresDriver
import Leaf

func configure(_ app: Application) async throws {
    // MARK: - Database
    let dbConfig = SQLPostgresConfiguration(
        hostname: Environment.get("DB_HOST") ?? "localhost",
        port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5432,
        username: Environment.get("DB_USER") ?? "politik",
        password: Environment.get("DB_PASSWORD") ?? "politik",
        database: Environment.get("DB_NAME") ?? "politik",
        tls: .disable
    )
    app.databases.use(.postgres(configuration: dbConfig), as: .psql)

    // MARK: - Migrations
    app.migrations.add(CreateInitialSchema())

    // MARK: - Leaf
    app.views.use(.leaf)

    // MARK: - Middleware
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.middleware.use(app.sessions.middleware)

    // MARK: - Services
    app.parlamentService = ParlamentService(client: app.client, logger: app.logger)
    app.claudeService = ClaudeService(
        client: app.client,
        logger: app.logger,
        apiKey: Environment.get("CLAUDE_API_KEY") ?? ""
    )

    // MARK: - Run Migrations
    try await app.autoMigrate()

    // MARK: - Routes
    try routes(app)
}
