import Vapor

struct AuthController {
    func loginForm(req: Request) async throws -> View {
        let error = req.session.data["loginError"]
        req.session.data["loginError"] = nil

        struct Context: Encodable {
            let title: String
            let error: String?
            let currentUser: UserContext?
        }
        return try await req.view.render("auth/login", Context(
            title: "Anmelden",
            error: error,
            currentUser: req.userContext
        ))
    }

    func login(req: Request) async throws -> Response {
        guard req.auth.has(User.self) else {
            req.session.data["loginError"] = "Ungültige E-Mail oder Passwort"
            return req.redirect(to: "/login")
        }
        return req.redirect(to: "/")
    }

    func logout(req: Request) async throws -> Response {
        req.auth.logout(User.self)
        req.session.destroy()
        return req.redirect(to: "/login")
    }
}
