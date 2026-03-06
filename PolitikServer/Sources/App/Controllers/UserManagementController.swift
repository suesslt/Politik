import Vapor
import Fluent

struct UserManagementController {
    // GET /admin/users
    func index(req: Request) async throws -> View {
        let currentUser = try req.auth.require(User.self)
        let users = try await User.query(on: req.db)
            .sort(\.$email)
            .all()

        struct Context: Encodable {
            let title: String
            let users: [User]
            let currentUser: UserContext?
            let flash: String?
        }
        let flash = req.session.data["flash"]
        req.session.data["flash"] = nil

        return try await req.view.render("admin/users/index", Context(
            title: "Benutzerverwaltung",
            users: users,
            currentUser: UserContext(name: currentUser.name, email: currentUser.email, isAdmin: currentUser.isAdmin),
            flash: flash
        ))
    }

    // GET /admin/users/new
    func createForm(req: Request) async throws -> View {
        let error = req.session.data["userError"]
        req.session.data["userError"] = nil

        struct Context: Encodable {
            let title: String
            let formUser: UserFormData?
            let error: String?
            let isEdit: Bool
            let currentUser: UserContext?
        }
        return try await req.view.render("admin/users/form", Context(
            title: "Neuer Benutzer",
            formUser: nil,
            error: error,
            isEdit: false,
            currentUser: req.userContext
        ))
    }

    // POST /admin/users
    func create(req: Request) async throws -> Response {
        let input = try req.content.decode(UserFormData.self)

        let existing = try await User.query(on: req.db)
            .filter(\.$email == input.email)
            .first()
        if existing != nil {
            req.session.data["userError"] = "E-Mail-Adresse bereits vergeben"
            return req.redirect(to: "/admin/users/new")
        }

        let passwordHash = try Bcrypt.hash(input.password)
        let user = User(
            email: input.email,
            passwordHash: passwordHash,
            name: input.name,
            role: input.role
        )
        try await user.save(on: req.db)
        req.session.data["flash"] = "Benutzer \(user.name) erstellt"
        return req.redirect(to: "/admin/users")
    }

    // GET /admin/users/:id/edit
    func editForm(req: Request) async throws -> View {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard let user = try await User.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        let error = req.session.data["userError"]
        req.session.data["userError"] = nil

        struct Context: Encodable {
            let title: String
            let formUser: UserFormData
            let error: String?
            let isEdit: Bool
            let userId: String
            let currentUser: UserContext?
        }
        return try await req.view.render("admin/users/form", Context(
            title: "Benutzer bearbeiten",
            formUser: UserFormData(
                email: user.email,
                name: user.name,
                role: user.role,
                password: ""
            ),
            error: error,
            isEdit: true,
            userId: user.id!.uuidString,
            currentUser: req.userContext
        ))
    }

    // POST /admin/users/:id
    func update(req: Request) async throws -> Response {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard let user = try await User.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        let input = try req.content.decode(UserFormData.self)

        let existing = try await User.query(on: req.db)
            .filter(\.$email == input.email)
            .filter(\.$id != id)
            .first()
        if existing != nil {
            req.session.data["userError"] = "E-Mail-Adresse bereits vergeben"
            return req.redirect(to: "/admin/users/\(id)/edit")
        }

        user.email = input.email
        user.name = input.name
        user.role = input.role

        if !input.password.isEmpty {
            user.passwordHash = try Bcrypt.hash(input.password)
        }

        try await user.save(on: req.db)
        req.session.data["flash"] = "Benutzer \(user.name) aktualisiert"
        return req.redirect(to: "/admin/users")
    }

    // POST /admin/users/:id/delete
    func delete(req: Request) async throws -> Response {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard let user = try await User.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        let currentUser = try req.auth.require(User.self)
        guard user.id != currentUser.id else {
            req.session.data["flash"] = "Sie können sich nicht selbst löschen"
            return req.redirect(to: "/admin/users")
        }

        let userName = user.name
        try await user.delete(on: req.db)
        req.session.data["flash"] = "Benutzer \(userName) gelöscht"
        return req.redirect(to: "/admin/users")
    }
}

// MARK: - Form DTO

struct UserFormData: Content {
    let email: String
    let name: String
    let role: String
    let password: String
}
