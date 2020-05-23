import Vapor

enum RouterError: Error {
    case missingClientID
    case missingClientSecret
    case missingSlackURL
}
/// Register your application's routes here.
public func routes(_ app: Application) throws {


    
//    let job = EmailJobContext(to: "to@to.com", from: "from@from.com", message: "message")
//    return queue.dispatch(job: job).transform(to: .ok)
    let hostname = "https://thumbworksbot.ngrok.io"
    guard let clientID = Environment.get("thumbworksbot_app_freshbooks_client_id") else {
        throw RouterError.missingClientID
    }
    guard let clientSecret = Environment.get("thumbworksbot_app_freshbooks_secret") else {
        throw RouterError.missingClientSecret
    }
    guard let slackURIString = Environment.get("thumbworksbot_app_freshbooks_slack_message_url") else {
        throw RouterError.missingSlackURL
    }

    let slackMessageURL = URI(string: slackURIString)



    let slack = SlackWebService(slackURL: slackMessageURL)
    let freshbookService = FreshbooksWebservice(hostname: hostname,
                                                clientID: clientID,
                                                clientSecret: clientSecret)
    let freshbooksController = FreshbooksController(freshbooksService: freshbookService, app: app)
    let webhookController = WebhookController(hostName: hostname,
                                              slackService: slack,
                                              freshbooksService: freshbookService)

    // The logged out view linking to the oauth flow
    app.get { req in
        return req.view.render("Landing", ["client_id" : clientID])
    }

    app.post("webhooks", use: freshbooksController.webhook)
    app.get("webhooks", use: freshbooksController.index)
    app.post("webhooks", "ready", use: webhookController.ready)
    app.get("freshbooks", "token", use: freshbooksController.accessToken)
    // TODO upgrade to v4
    app.sessions.configuration.cookieName = "thumbworksbot"
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
    protected.get("invoices", use: webhookController.getInvoices)
}

