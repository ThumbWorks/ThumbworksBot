import Vapor
import Authentication
import FluentSQLite

enum RouterError: Error {
    case noClientIDSetInEnvironment
    case noClientSecretSetInEnvironment
}
/// Register your application's routes here.
public func routes(_ router: Router) throws {
    let localhost = "https://thumbworksbot.ngrok.io"
       guard let client_id = Environment.get("thumbworksbot_app_freshbooks_client_id") else {
           throw RouterError.noClientIDSetInEnvironment
       }
       guard let client_secret = Environment.get("thumbworksbot_app_freshbooks_secret") else {
           throw RouterError.noClientSecretSetInEnvironment
       }

    let freshbooksController = FreshbooksController(clientID: client_id, clientSecret: client_secret, callbackHost: localhost)
    let userController = UserController()

    // The logged out view linking to the oauth flow
    router.get { req in
        return try req.view().render("Landing", ["client_id" : client_id])
    }

    router.post("webhook", use: freshbooksController.webhook)
    router.get("webhook", use: freshbooksController.index)
    router.post("registerNewWebhook", use: freshbooksController.registerNewWebhook)
    router.post("webhook/ready", use: freshbooksController.webhookReady)
    router.get("freshbooks/token", use: freshbooksController.accessToken)

    let session = User.authSessionsMiddleware()
    let authenticatedUserGroup = router.grouped(session)
    authenticatedUserGroup.get("freshbooks/auth", use: freshbooksController.freshbooksAuth)
    authenticatedUserGroup.get("user/webhooks", use: userController.webhooks)

}
