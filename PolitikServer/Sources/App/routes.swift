import Vapor

func routes(_ app: Application) throws {
    // MARK: - Auth Routes (Public)
    let authController = AuthController()
    app.get("login", use: authController.loginForm)
    app.grouped(User.credentialsAuthenticator())
        .post("login", use: authController.login)
    app.post("logout", use: authController.logout)

    // MARK: - Protected Web Routes (Session Auth)
    let protected = app.grouped(EnsureAuthenticatedMiddleware())

    let sessionController = SessionController()
    protected.get(use: sessionController.index)
    protected.get("sessions", use: sessionController.index)
    protected.get("sessions", ":id", use: sessionController.show)
    protected.post("sessions", ":id", "sync", use: sessionController.sync)

    let geschaeftController = GeschaeftController()
    protected.get("geschaefte", ":id", use: geschaeftController.show)
    protected.post("geschaefte", ":id", "analyze", use: geschaeftController.analyze)

    let parlamentarierController = ParlamentarierController()
    protected.get("parlamentarier", use: parlamentarierController.index)
    protected.get("parlamentarier", ":personNumber", use: parlamentarierController.show)
    protected.post("parlamentarier", ":personNumber", "analyze", use: parlamentarierController.analyze)

    let reportController = DailyReportController()
    protected.get("reports", use: reportController.index)
    protected.get("reports", ":id", use: reportController.show)
    protected.post("reports", "generate", use: reportController.generate)

    let syncController = SyncController()
    protected.get("sync", use: syncController.index)
    protected.post("sync", "sessions", use: syncController.syncSessions)
    protected.get("sync", "status", use: syncController.status)
    protected.post("sync", "load-sessions", use: syncController.loadSessions)

    let settingsController = SettingsController()
    protected.get("settings", use: settingsController.index)

    // MARK: - Admin Routes (Admin Only)
    let admin = protected.grouped(EnsureAdminMiddleware())

    let userController = UserManagementController()
    admin.get("admin", "users", use: userController.index)
    admin.get("admin", "users", "new", use: userController.createForm)
    admin.post("admin", "users", use: userController.create)
    admin.get("admin", "users", ":id", "edit", use: userController.editForm)
    admin.post("admin", "users", ":id", use: userController.update)
    admin.post("admin", "users", ":id", "delete", use: userController.delete)

    // MARK: - API Routes (Basic Auth)
    let apiAuth = app.grouped("api", "v1")
        .grouped(User.authenticator())
        .grouped(User.guardMiddleware())

    let apiSessions = apiAuth.grouped("sessions")
    apiSessions.get(use: sessionController.apiIndex)
    apiSessions.get(":id", use: sessionController.apiShow)
    apiSessions.post(":id", "sync", use: sessionController.apiSync)

    let apiGeschaefte = apiAuth.grouped("geschaefte")
    apiGeschaefte.get(":id", use: geschaeftController.apiShow)
    apiGeschaefte.post(":id", "analyze", use: geschaeftController.apiAnalyze)

    let apiParlamentarier = apiAuth.grouped("parlamentarier")
    apiParlamentarier.get(use: parlamentarierController.apiIndex)
    apiParlamentarier.get(":personNumber", use: parlamentarierController.apiShow)

    let apiReports = apiAuth.grouped("reports")
    apiReports.get(use: reportController.apiIndex)
    apiReports.get(":id", use: reportController.apiShow)
}
