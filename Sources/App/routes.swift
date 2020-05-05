import Vapor

enum RouterError: Error {
    case noClientIDSetInEnvironment
    case noClientSecretSetInEnvironment
}
/// Register your application's routes here.
public func routes(_ router: Router) throws {
    // Basic "It works" example
    router.get { req in
        return "It works!"
    }   
    
    // Basic "Hello, world!" example
    router.get("hello") { req in
        return "Hello, world!"
    }

    let localhost = "https://156ace05.ngrok.io"
    guard let client_id = Environment.get("thumbworksbot_app_freshbooks_client_id") else {
        throw RouterError.noClientIDSetInEnvironment
    }
    guard let client_secret = Environment.get("thumbworksbot_app_freshbooks_secret") else {
        throw RouterError.noClientSecretSetInEnvironment
    }

    let freshbooksController = FreshbooksController(clientID: client_id, clientSecret: client_secret, callbackHost: localhost)
    router.post("webhook", use: freshbooksController.webhook)
    router.post("registerNewWebhook", use: freshbooksController.registerNewWebhook)
    router.post("webhook/ready", use: freshbooksController.webhookReady)
    router.get("freshbooks/auth", use: freshbooksController.freshbooksAuth)
    router.get("freshbooks/token", use: freshbooksController.accessToken)

    // Example of configuring a controller
    let todoController = TodoController()
    router.get("todos", use: todoController.index)
    router.post("todos", use: todoController.create)
    router.delete("todos", Todo.parameter, use: todoController.delete)
}
