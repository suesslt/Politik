import Fluent
import Vapor

/// DataStore-Implementierung mit Fluent (PostgreSQL, SQLite, etc.).
struct FluentDataStore: DataStore, Sendable {
    let database: Database
    let backendName: String

    init(database: Database, backendName: String = "Fluent") {
        self.database = database
        self.backendName = backendName
    }

    func find<M: Model>(_ type: M.Type, id: M.IDValue) async throws -> M? {
        try await type.find(id, on: database)
    }

    func all<M: Model>(_ type: M.Type) async throws -> [M] {
        try await type.query(on: database).all()
    }

    func save<M: Model>(_ model: M) async throws {
        try await model.save(on: database)
    }

    func delete<M: Model>(_ model: M) async throws {
        try await model.delete(on: database)
    }

    func query<M: Model>(_ type: M.Type) -> QueryBuilder<M> {
        type.query(on: database)
    }

    func transaction<T: Sendable>(
        _ closure: @escaping @Sendable (DataStore) async throws -> T
    ) async throws -> T {
        try await database.transaction { db in
            let txStore = FluentDataStore(database: db, backendName: self.backendName)
            return try await closure(txStore)
        }
    }
}

// MARK: - Vapor Request Extension

extension Request {
    var dataStore: DataStore {
        FluentDataStore(database: self.db, backendName: "PostgreSQL")
    }
}

// MARK: - Application Extension

extension Application {
    var dataStore: DataStore {
        FluentDataStore(database: self.db, backendName: "PostgreSQL")
    }
}
