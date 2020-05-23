import App
import XCTVapor
@testable import App

final class AppTests: XCTestCase {
    var application: Application! = nil
    let freshbooks = FreshbooksWebServicingMock()
    let slack = SlackWebServicingMock()
    lazy var webhookController = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks)

    override func setUp() {
        application = Application(Environment.testing)
        freshbooks.authHandler = TestData.freshbooksAuthHandler
        freshbooks.fetchUserHandler = TestData.fetchUserHandler
        let deps = ApplicationDependencies(freshbooksServicing: freshbooks, slackServicing: slack, hostname: "", clientID: "'")
        try? configure(application, dependencies: deps)
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

}
