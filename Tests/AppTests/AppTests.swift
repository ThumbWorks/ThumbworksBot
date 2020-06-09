import App
import XCTVapor
@testable import App


final class AppTests: XCTestCase {
    var application: Application! = nil
    let freshbooks = FreshbooksWebServicingMockWithDefaultHandlers()
    let slack = SlackWebServicingMock()
    lazy var webhookController = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks)
    let testUser = User(responseObject: TestData.userResponseObject, accessToken: TestData.userAccessToken)

    // For authenticated calls we need to store the session cookies
    var vaporSessionCookie: String = ""

    override func setUp() {
        application = Application(Environment.testing)
        defer {application.shutdown()}
        let deps = ApplicationDependencies(freshbooksServicing: freshbooks,
                                           slackServicing: slack,
                                           hostname: "",
                                           clientID: "'",
                                           databaseURLString: nil) { sessionID, request in
                                            let promise = request.eventLoop.makePromise(of: Void.self)
                                            DispatchQueue.global().async {
                                                promise.succeed(Void())
                                            }
                                            return promise.futureResult
        }
        
        do {
            try configure(application, dependencies: deps)
            try? testUser.save(on: application.db).wait()
            try? Business(business: TestData.business).save(on: application.db).wait()
            let req = Request(application: application, on: application.eventLoopGroup.next())
            let userAuthenticator = UserSessionAuthenticator(authenticationClosure: deps.authenticationClosure)
            try userAuthenticator.authenticate(sessionID: TestData.userAccessToken, for: req).wait()
        } catch {
            print(error)
        }
    }

//    func testFetchInvoice() throws {
//        let req = Request(application: application, on: application.eventLoopGroup.next())
//        let accountID = "accountID"
//        let invoiceID = 123
//        let accessToken = "AccessToken"
////        freshbooks.fetchInvoiceHandler = TestData.fetchInvoiceHandler
//        do {
//            // fetch the invoice
//            let invoice = try webhookController.getInvoice(accountID: accountID, invoiceID: invoiceID, accessToken: accessToken, on: req)
//                .map({ invoice in
//                    return invoice
//                }).wait()
//            // verify that it's what we planned to send back
//            XCTAssertEqual(invoice, TestData.invoice)
//        } catch {
//            XCTFail(error.localizedDescription)
//        }
//        XCTAssertEqual(freshbooks.fetchInvoiceCallCount, 1)
//    }

//    func testAuthBadRequest() throws {
//        try application.test(.GET, "freshbooks/auth") { res in
//            XCTAssertEqual(res.status, .badRequest)
//        }
//    }

//    func testOAuthGetToken() throws {
//        // When the user attempts the auth call with an auth request code
//        try application.test(.GET, "freshbooks/auth", beforeRequest: { request in
//            try request.query.encode(TestData.authRequest)
//        }) { res in
//            // Auth call to freshbooks happens
//            XCTAssertEqual(freshbooks.authCallCount, 1)
//
//            // Fetch user from freshbooks
//            XCTAssertEqual(freshbooks.fetchUserCallCount, 1)
//
//            // Return status should be .ok
//            XCTAssertEqual(res.status, .ok)
//        }
//    }

//    func testCreateWebhookWhileLoggedOut() throws {
//        // When the user attempts the auth call with an auth request code
//        try application.test(.POST, "webhooks/new") { res in
//            // Should be unauthorized
//            XCTAssertEqual(res.status, .unauthorized)
//        }
//    }


//    func testOauthFlow() throws {
//        try application.test(.GET, "freshbooks/auth", beforeRequest: { request in
//            let content = AuthRequest(code: "MockAuthCode")
//            try request.query.encode(content)
//        }) { res in
//            // Auth call to freshbooks happens
//            XCTAssertEqual(freshbooks.authCallCount, 1)
//
//            // Fetch user from freshbooks
//            XCTAssertEqual(freshbooks.fetchUserCallCount, 1)
//
//            // Return status should be .ok
//            XCTAssertEqual(res.status, .ok)
//        }
//    }

    private func setVaporCookie() throws {
        // As part of the setup process, run the oauth flow
         try application.test(.GET, "freshbooks/auth", beforeRequest: { request in
             let content = AuthRequest(code: "MockAuthCode")
             try request.query.encode(content)
         }) { res in
             vaporSessionCookie = res.headers["set-cookie"].first!
         }
    }

//    func testCreateWebhook() throws {
//        try setVaporCookie()
//        // Now that we've authenticated a user, run the actual test
//        try application.test(.POST, "webhooks/new",
//                             headers: ["Cookie" : vaporSessionCookie]) { res in
//                                // Auth call to freshbooks happens
//                                XCTAssertEqual(freshbooks.registerNewWebhookCallCount, 1)
//
//                                // Return status should be .ok
//                                XCTAssertEqual(res.status, .ok)
//        }
//    }

//    func testExecuteWebhook() throws {
//        // set custom slack handler
//        slack.sendSlackPayloadHandler = { string, emoji, request in
//            XCTAssertEqual(string, "New invoice created to Uber Technologies, Inc, for 123 USD")
//            XCTAssertEqual(emoji, Emoji.uber)
//            return request.successPromiseAfterGlobalDispatchASync()
//        }
//        try application.test(.POST, "webhooks/ready", beforeRequest: { request in
//            
//            let content = FreshbooksWebhookTriggeredContent(freshbooksUserID: 123, name: "abc", objectID: 123, verified: true, verifier: nil, accountID: "abc")
//            try request.content.encode(content)
//        }) { res in
//            // fetch invoice from freshbooks
//            XCTAssertEqual(freshbooks.fetchInvoiceCallCount, 1)
//
//            // send request to slack
//            XCTAssertEqual(slack.sendSlackPayloadCallCount, 1)
//
//            // Return status should be .ok
//            XCTAssertEqual(res.status, .ok)
//        }
//    }
}
