import Vapor

func routes(_ app: Application) throws {
    // MARK: - Web Routes (Leaf Templates)
    let sessionController = SessionController()
    app.get(use: sessionController.index)
    app.get("sessions", use: sessionController.index)
    app.get("sessions", ":id", use: sessionController.show)
    app.post("sessions", ":id", "sync", use: sessionController.sync)

    let geschaeftController = GeschaeftController()
    app.get("geschaefte", ":id", use: geschaeftController.show)
    app.post("geschaefte", ":id", "analyze", use: geschaeftController.analyze)

    let parlamentarierController = ParlamentarierController()
    app.get("parlamentarier", use: parlamentarierController.index)
    app.get("parlamentarier", ":personNumber", use: parlamentarierController.show)
    app.post("parlamentarier", ":personNumber", "analyze", use: parlamentarierController.analyze)

    let reportController = DailyReportController()
    app.get("reports", use: reportController.index)
    app.get("reports", ":id", use: reportController.show)
    app.post("reports", "generate", use: reportController.generate)

    let syncController = SyncController()
    app.get("sync", use: syncController.index)
    app.post("sync", "sessions", use: syncController.syncSessions)
    app.get("sync", "status", use: syncController.status)
    app.post("sync", "load-sessions", use: syncController.loadSessions)

    let settingsController = SettingsController()
    app.get("settings", use: settingsController.index)

    // MARK: - API Routes (JSON)
    let api = app.grouped("api", "v1")

    let apiSessions = api.grouped("sessions")
    apiSessions.get(use: sessionController.apiIndex)
    apiSessions.get(":id", use: sessionController.apiShow)
    apiSessions.post(":id", "sync", use: sessionController.apiSync)

    let apiGeschaefte = api.grouped("geschaefte")
    apiGeschaefte.get(":id", use: geschaeftController.apiShow)
    apiGeschaefte.post(":id", "analyze", use: geschaeftController.apiAnalyze)

    let apiParlamentarier = api.grouped("parlamentarier")
    apiParlamentarier.get(use: parlamentarierController.apiIndex)
    apiParlamentarier.get(":personNumber", use: parlamentarierController.apiShow)

    let apiReports = api.grouped("reports")
    apiReports.get(use: reportController.apiIndex)
    apiReports.get(":id", use: reportController.apiShow)
}
