import Vapor

struct UserContext: Encodable {
    let name: String
    let email: String
    let isAdmin: Bool
}

extension Request {
    var userContext: UserContext? {
        guard let user = auth.get(User.self) else { return nil }
        return UserContext(name: user.name, email: user.email, isAdmin: user.isAdmin)
    }
}
