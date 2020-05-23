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
           try? configure(application)
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
}
