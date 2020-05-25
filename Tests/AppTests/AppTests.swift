import App
import XCTVapor
@testable import App

final class AppTests: XCTestCase {
    var application: Application! = nil
    let freshbooks = FreshbooksWebServicingMock()
    let slack = SlackWebServicingMock()
    lazy var webhookController = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks)
    let testUser = User(responseObject: TestData.userResponseObject, accessToken: TestData.userAccessToken)

    override func setUp() {
        application = Application(Environment.testing)
        freshbooks.authHandler = TestData.freshbooksAuthHandler
        freshbooks.fetchUserHandler = TestData.fetchUserHandler
        let deps = ApplicationDependencies(freshbooksServicing: freshbooks, slackServicing: slack, hostname: "", clientID: "'")
        try? configure(application, dependencies: deps)
        try? testUser.save(on: application.db).wait()
        try? Business(business: TestData.business).save(on: application.db).wait()
        let req = Request(application: application, on: application.eventLoopGroup.next())
        _ = try? UserSessionAuthenticator().authenticate(sessionID: TestData.userAccessToken, for: req).wait()
    }

    func testFetchInvoice() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())
        let accountID = "accountID"
        let invoiceID = 123
        let accessToken = "AccessToken"
        freshbooks.fetchInvoiceHandler = TestData.fetchInvoiceHandler
        do {
            // fetch the invoice
            let invoice = try webhookController.getInvoice(accountID: accountID, invoiceID: invoiceID, accessToken: accessToken, on: req)
                .map({ invoice in
                    return invoice
                }).wait()
            // verify that it's what we planned to send back
            XCTAssertEqual(invoice, TestData.invoice)
        } catch {
            XCTFail(error.localizedDescription)
        }
        XCTAssertEqual(freshbooks.fetchInvoiceCallCount, 1)
    }

    func testAuthBadRequest() throws {
        try application.test(.GET, "freshbooks/auth") { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testOAuthGetToken() throws {
        // When the user attempts the auth call with an auth request code
        try application.test(.GET, "freshbooks/auth", beforeRequest: { request in
            try request.query.encode(TestData.authRequest)
        }) { res in
            // Auth call to freshbooks happens
            XCTAssertEqual(freshbooks.authCallCount, 1)

            // Fetch user from freshbooks
            XCTAssertEqual(freshbooks.fetchUserCallCount, 1)

            // Return status should be .ok
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testCreateWebhookWhileLoggedOut() throws {
        // When the user attempts the auth call with an auth request code
        try application.test(.POST, "webhooks/new") { res in
            // Should be unauthorized
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testCreateWebhook() throws {
        // When the user attempts the auth call with an auth request code
        try application.test(.POST, "webhooks/new", beforeRequest: { request in
            try request.query.encode(TestData.authRequest)
        }) { res in
            // Auth call to freshbooks happens
            XCTAssertEqual(freshbooks.registerNewWebhookCallCount, 1)

            // Fetch user from freshbooks
            XCTAssertEqual(freshbooks.fetchUserCallCount, 1)

            // Return status should be .ok
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testExecuteWebhook() throws {
        freshbooks.fetchInvoiceHandler = TestData.fetchInvoiceHandler
        // set custom slack handler
        slack.sendSlackPayloadHandler = { string, emoji, request in
            XCTAssertEqual(string, "New invoice created to Uber Technologies, Inc, for 123 USD")
            XCTAssertEqual(emoji, Emoji.uber)
            return request.successPromiseAfterGlobalDispatchASync()
        }
        try application.test(.POST, "webhooks/ready", beforeRequest: { request in
            let content = FreshbooksWebhookTriggeredContent(freshbooksUserID: 123, name: "abc", objectID: 123, verified: true, verifier: nil, accountID: "abc")
            try request.content.encode(content)
        }) { res in
            // fetch invoice from freshbooks
            XCTAssertEqual(freshbooks.fetchInvoiceCallCount, 1)

            // send request to slack
            XCTAssertEqual(slack.sendSlackPayloadCallCount, 1)

            // Return status should be .ok
            XCTAssertEqual(res.status, .ok)
        }
    }
}
