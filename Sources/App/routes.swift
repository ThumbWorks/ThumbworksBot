import Vapor

public enum RouterError: Error {
    case missingClientID
    case missingClientSecret
    case missingSlackURL
    case missingHostName
    case missingDatabaseHostURL
}

public struct ApplicationDependencies {
    let freshbooksServicing: FreshbooksWebServicing
    let slackServicing: SlackWebServicing
    let hostname: String
    let clientID: String
    let databaseURLString: String?

    public init(freshbooksServicing: FreshbooksWebServicing, slackServicing: SlackWebServicing, hostname: String, clientID: String, databaseURLString: String?) {
        self.freshbooksServicing = freshbooksServicing
        self.slackServicing = slackServicing
        self.hostname = hostname
        self.clientID = clientID
        self.databaseURLString = databaseURLString
    }
}
/// Register your application's routes here.
public func routes(_ app: Application, dependencies: ApplicationDependencies) throws {

    let freshbooksController = FreshbooksController(freshbooksService: dependencies.freshbooksServicing, app: app)
    let webhookController = WebhookController(hostName: dependencies.hostname,
                                              slackService: dependencies.slackServicing,
                                              freshbooksService: dependencies.freshbooksServicing)

    // The logged out view linking to the oauth flow
    app.get { req in
        return req.view.render("Landing", ["client_id" : dependencies.clientID, "hostname": dependencies.hostname])
    }

    app.post("webhooks", use: freshbooksController.webhook)
    app.get("webhooks", use: freshbooksController.index)
    app.post("webhooks", "ready", use: webhookController.ready)
    app.get("freshbooks", "token", use: freshbooksController.accessToken)
    // Configures cookie value creation.
    app.sessions.configuration.cookieFactory = { sessionID in
        .init(string: sessionID.string, isSecure: true)
    }

//    let authenticatedUserGroup = app.grouped([session])

    let protected = app.grouped(app.sessions.middleware,
                                UserSessionAuthenticator())

    protected.get("freshbooks", "auth", use: freshbooksController.freshbooksAuth)
    protected.get("webhooks", use: webhookController.webhooks)
    protected.get("allWebhooks", use: webhookController.allWebhooks)
    protected.post("webhooks", "new", use: webhookController.registerNewWebhook)
    protected.get("webhooks", "delete", use: webhookController.deleteWebhook)
    protected.get("invoices", use: freshbooksController.getInvoices)
}

