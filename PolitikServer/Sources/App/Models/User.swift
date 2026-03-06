import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    var email: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Field(key: "name")
    var name: String

    @Field(key: "role")
    var role: String

    @Field(key: "created_at")
    var createdAt: Date

    var isAdmin: Bool {
        role == "admin"
    }

    init() {}

    init(
        id: UUID? = nil,
        email: String,
        passwordHash: String,
        name: String,
        role: String = "user"
    ) {
        self.id = id
        self.email = email
        self.passwordHash = passwordHash
        self.name = name
        self.role = role
        self.createdAt = Date()
    }
}

// MARK: - Authentication

extension User: ModelAuthenticatable {
    static let usernameKey = \User.$email
    static let passwordHashKey = \User.$passwordHash

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}

extension User: ModelSessionAuthenticatable {}
extension User: ModelCredentialsAuthenticatable {}
