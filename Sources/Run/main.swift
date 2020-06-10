import App
import Vapor

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = Application(env)
defer { app.shutdown() }
try configure(app, dependencies: generateDependencies())
try app.run()

func generateDependencies() throws -> ApplicationDependencies {
    guard let hostName = Environment.get("thumbworksbot_app_freshbooks_hostname") else {
          throw RouterError.missingHostName
      }
    guard let clientID = Environment.get("thumbworksbot_app_freshbooks_client_id") else {
        throw RouterError.missingClientID
    }
    guard let clientSecret = Environment.get("thumbworksbot_app_freshbooks_secret") else {
        throw RouterError.missingClientSecret
    }
    guard let slackURIString = Environment.get("thumbworksbot_app_freshbooks_slack_message_url") else {
        throw RouterError.missingSlackURL
    }

    let dbHost = Environment.get("DATABASE_URL")

    let slackMessageURL = URI(string: slackURIString)
    let slackServicing = SlackWebService(slackURL: slackMessageURL)
    let freshbookServicing = FreshbooksWebservice(hostname: hostName,
                                                  clientID: clientID,
                                                  clientSecret: clientSecret)

    return ApplicationDependencies(freshbooksServicing: freshbookServicing,
                                   slackServicing: slackServicing,
                                   hostname: hostName,
                                   clientID: clientID,
                                   clientSecret: clientSecret,
                                   databaseURLString: dbHost) { sessionID, request in
                                    // For the actual app, we use the userID that is passed from the request from freshbooks
                                    User.query(on: request.db)
                                        .filter(\.$accessToken, .equal, sessionID)
                                        .first()
                                        .unwrap(or: Abort(.notFound))
                                        .map { user in
                                            request.auth.login(user)
                                    }
    }
}
