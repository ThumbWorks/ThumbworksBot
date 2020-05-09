import Vapor
import Authentication
import FluentSQLite

enum RouterError: Error {
    case missingClientID
    case missingClientSecret
    case missingSlackURL
}
/// Register your application's routes here.
public func routes(_ router: Router) throws {
    let localhost = "https://thumbworksbot.ngrok.io"
       guard let clientID = Environment.get("thumbworksbot_app_freshbooks_client_id") else {
           throw RouterError.missingClientID
       }
       guard let clientSecret = Environment.get("thumbworksbot_app_freshbooks_secret") else {
           throw RouterError.missingClientSecret
       }
    guard let urlString = Environment.get("thumbworksbot_app_freshbooks_slack_message_url"), let slackMessageURL = URL(string: urlString) else {
        throw RouterError.missingSlackURL
    }

    let freshbooksController = FreshbooksController(clientID: clientID, clientSecret: clientSecret, callbackHost: localhost)
    let webhookController = WebhookController(hostName: localhost, slackURL: slackMessageURL)

    // The logged out view linking to the oauth flow
    router.get { req in
        return try req.view().render("Landing", ["client_id" : clientID])
    }

    router.post("webhooks", use: freshbooksController.webhook)
    router.get("webhooks", use: freshbooksController.index)
    router.post("webhooks/ready", use: webhookController.ready)
    router.get("freshbooks/token", use: freshbooksController.accessToken)

    let session = User.authSessionsMiddleware()
    let authenticatedUserGroup = router.grouped(session)
    authenticatedUserGroup.get("freshbooks/auth", use: freshbooksController.freshbooksAuth)
    authenticatedUserGroup.get("/webhooks", use: webhookController.webhooks)
    authenticatedUserGroup.get("/allWebhooks", use: webhookController.allWebhooks)
    authenticatedUserGroup.post("/webhooks/new", use: webhookController.registerNewWebhook)
    authenticatedUserGroup.get("/webhooks/delete", use: webhookController.deleteWebhook)
}

