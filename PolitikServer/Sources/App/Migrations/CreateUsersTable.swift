import Fluent
import Vapor

struct CreateUsersTable: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .id()
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("name", .string, .required)
            .field("role", .string, .required, .sql(.default("user")))
            .field("created_at", .datetime, .required)
            .unique(on: "email")
            .create()

        // Seed admin user
        let adminPassword = try Bcrypt.hash("admin123")
        let admin = User(
            email: "admin@politik.ch",
            passwordHash: adminPassword,
            name: "Administrator",
            role: "admin"
        )
        try await admin.save(on: database)
    }

    func revert(on database: Database) async throws {
        try await database.schema("users").delete()
    }
}
