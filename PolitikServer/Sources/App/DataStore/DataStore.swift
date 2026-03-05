import Fluent
import Vapor

/// Abstrahiert den Datenzugriff für alle Persistenz-Backends.
protocol DataStore: Sendable {
    /// The underlying Fluent database for direct query access.
    var database: Database { get }

    /// Backend name for logging/diagnostics.
    var backendName: String { get }

    /// Find entity by ID.
    func find<M: Model>(_ type: M.Type, id: M.IDValue) async throws -> M?

    /// Fetch all entities of a type.
    func all<M: Model>(_ type: M.Type) async throws -> [M]

    /// Save (insert or update) an entity.
    func save<M: Model>(_ model: M) async throws

    /// Delete an entity.
    func delete<M: Model>(_ model: M) async throws

    /// Create a query builder for complex queries.
    func query<M: Model>(_ type: M.Type) -> QueryBuilder<M>

    /// Execute operations atomically in a transaction.
    func transaction<T: Sendable>(
        _ closure: @escaping @Sendable (DataStore) async throws -> T
    ) async throws -> T
}
