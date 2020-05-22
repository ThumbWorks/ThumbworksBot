//
//  WebhookControllerTests.swift
//  AppTests
//
//  Created by Roderic Campbell on 5/8/20.
//

import XCTest
import XCTVapor
@testable import App

enum TestingError: Error {
    case slackFail
}

extension FreshbooksInvoice {
    convenience init(freshbooksID: Int, status: Int, paymentStatus: String, currentOrganization: String, amount: FreshbooksInvoice.Amount, createdAt: Date) {
        self.init()
        self.freshbooksID = freshbooksID
        self.status = status
        self.paymentStatus = paymentStatus
        self.currentOrganization = currentOrganization
        self.amount = amount
        self.createdAt = createdAt
        self.init()
    }
}
class WebhookControllerTests: XCTestCase {
    var application: Application! = nil

    var testUser: User?
    static let invoice = FreshbooksInvoiceContent(freshbooksID: 1,
                                                  status: 2,
                                                  paymentStatus: "unpaid",
                                                  currentOrganization: Emoji.uber.rawValue,
                                                  amount: FreshbooksInvoiceContent.Amount(amount: "123", code: "USD"),
                                                  createdAt: Date())
    let business = BusinessPayload(id: 345, name: "Thumbworks", accountID: "businessAccountID")
    lazy var membership = MembershipPayload(id: 123, role: "manager", business: business)
    lazy var userResponseObject = UserResponseObject(id: 123, firstName: "rod", lastName: "campbell", businessMemberships: [membership])
    let freshbooksVerifiedWebhookContent = FreshbooksWebhookTriggeredContent(freshbooksUserID: 1,
                                                                             name: "create an invoice",
                                                                             objectID: 123,
                                                                             verified: true,
                                                                             verifier: nil,
                                                                             accountID: "123")
    let freshbooksVerifyContent = FreshbooksWebhookTriggeredContent(freshbooksUserID: 1,
                                                                    name: "create an invoice",
                                                                    objectID: 123,
                                                                    verified: false,
                                                                    verifier: "abc",
                                                                    accountID: "123")
    let slack = SlackWebServicingMock()
    let freshbooks = FreshbooksWebServicingMock()
    let userAccessToken = "accessTokenOfUserSavedInDB"
    lazy var controller = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks)
    
    var fetchInvoiceHandler: ((String, Int, String, Request) throws -> (EventLoopFuture<FreshbooksInvoiceContent>))? = { a, b, c, request in
        let promise = request.eventLoop.makePromise(of: FreshbooksInvoiceContent.self)
        DispatchQueue.global().async {
            let date = Date(timeIntervalSince1970: 123)
            promise.succeed(WebhookControllerTests.invoice)
        }
        return promise.futureResult
    }
    
    let failSlackRequestHandler: ((Request) throws -> (EventLoopFuture<Response>))? = { request in
        let promise = request.eventLoop.makePromise(of: Response.self)
        DispatchQueue.global().async {
            promise.fail(TestingError.slackFail)
        }
        return promise.futureResult
    }

    override func setUp() {
        application = Application(Environment.testing)
        try? configure(application)

        let req = Request(application: application, on: application.eventLoopGroup.next())
        testUser = User(responseObject: userResponseObject, accessToken: userAccessToken)
        testUser?.id = UUID()
        try? testUser?.save(on: req.db).wait()
        try? Business(business: business).save(on: req.db).wait()

        do {
            let _ = try Webhook(webhookID: 123, userID: try testUser!.requireID()).save(on: req.db).wait()
        } catch {
            print(error)
        }
    }

    override func tearDown() { }
    func testSlackMessageGetsSentOnVerifiedWebhook() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())
        var expectedEmoji: Emoji? = Emoji.apple
        var expectedSlackPayloadString: String = "shouldChange"
        
        // set custom slack handler
        slack.sendSlackPayloadHandler = { string, emoji, request in
            expectedEmoji = emoji
            expectedSlackPayloadString = string
            return request.successPromiseAfterGlobalDispatchASync()
        }
        
        // use default fetchInvoiceHandler
        freshbooks.fetchInvoiceHandler = fetchInvoiceHandler
        
        try? req.content.encode(freshbooksVerifiedWebhookContent)
        // Run the command
        XCTAssertEqual(try controller.ready(req).wait(), HTTPStatus.ok)
        
        // validate the results
        XCTAssertEqual(expectedEmoji, Emoji.uber)
        XCTAssertEqual(expectedSlackPayloadString, "New invoice created to Uber Technologies, Inc, for 123 USD")
        
        XCTAssertEqual(slack.sendSlackPayloadCallCount, 1)
        XCTAssertEqual(freshbooks.fetchInvoiceCallCount, 1)

    }
    
    func testFreshbooksVerificationWebhook() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())

        // Verify that we are able to fetch the user from the database and the access token set is being sent to confirm webhook
        freshbooks.confirmWebhookHandler = { token, request in
            XCTAssertEqual(token, self.userAccessToken)
            return request.successPromiseAfterGlobalDispatchASync()
        }

        do {
            try req.content.encode(freshbooksVerifyContent)
            let status = try controller.ready(req).wait()
            XCTAssertEqual(status, HTTPStatus.ok)
            XCTAssertEqual(freshbooks.confirmWebhookCallCount, 1)
            XCTAssertEqual(slack.sendSlackPayloadCallCount, 0)
        } catch UserError.noUserWithThatAccessToken {
            XCTFail("Failed to fetch user with given access token from database")
        }
        catch WebhookError.webhookNotFound {
            XCTFail("webhookNotFound. Possibly forgot to create a webhook in the database during the test")
        }
        catch {
            print(error)
            XCTFail(error.localizedDescription)
        }
        XCTAssertEqual(freshbooks.confirmWebhookCallCount, 1)

    }
    
    func testFetchInvoice() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())
        let accountID = "accountID"
        let invoiceID = 123
        let accessToken = "AccessToken"
        freshbooks.fetchInvoiceHandler = fetchInvoiceHandler
        do {
            // fetch the invoice
            let invoice = try controller.getInvoice(accountID: accountID, invoiceID: invoiceID, accessToken: accessToken, on: req)
                .map({ invoice in
                    return invoice
                }).wait()
            // verify that it's what we planned to send back
            XCTAssertEqual(invoice, WebhookControllerTests.invoice)
        } catch {
            XCTFail(error.localizedDescription)
        }
        XCTAssertEqual(freshbooks.fetchInvoiceCallCount, 1)

    }

    func testDeleteWebhook() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())

        freshbooks.deleteWebhookHandler = { userID, webhookID, request in
            XCTAssertNotNil(self.business.accountID)
            XCTAssertEqual(self.business.accountID, userID)
            return request.successPromiseAfterGlobalDispatchASync()
        }
        _ = try UserSessionAuthenticator().authenticate(sessionID: userAccessToken, for: req).wait()
        try req.query.encode(TestingDeleteWebhookRequestPayload(id: 123))

        // Ensure that the webhook exists before we attempt to delete it
        XCTAssertEqual(try Webhook.query(on: req.db).all().wait().count, 1)

        do {
            // Delete the webhook
            _ = try controller.deleteWebhook(req).wait()

            // Ensure that the webhook is out of the database
            XCTAssertEqual(try Webhook.query(on: req.db).all().wait().count, 0)
        } catch {
            XCTFail(error.localizedDescription)
        }

        XCTAssertEqual(freshbooks.deleteWebhookCallCount, 1)
    }
}
private struct TestingDeleteWebhookRequestPayload: Codable {
    let id: Int
}
extension Request {
    fileprivate func successPromiseAfterGlobalDispatchASync() -> EventLoopFuture<ClientResponse> {
        let promise = eventLoop.makePromise(of: ClientResponse.self)
        DispatchQueue.global().async {
            let response = ClientResponse(status: .ok, headers: [:], body: nil)
            promise.succeed(response)
        }
        return promise.futureResult
    }
}
