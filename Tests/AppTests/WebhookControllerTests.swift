//
//  WebhookControllerTests.swift
//  AppTests
//
//  Created by Roderic Campbell on 5/8/20.
//

import XCTest
import Vapor
@testable import App

enum TestingError: Error {
    case slackFail
}
class WebhookControllerTests: XCTestCase {
    let thisApp = try! app(Environment(name: "test", isRelease: false))
    static let invoice = FreshbooksInvoice(id: 1,
                                           status: 2,
                                           paymentStatus: "unpaid",
                                           currentOrganization: Emoji.uber.rawValue,
                                           amount: FreshbooksInvoice.Amount(amount: "123", code: "USD"),
                                           createdAt: Date())
    let business = BusinessPayload(id: 345, name: "Thumbworks", accountID: "businessAccountID")
    lazy var membership = MembershipPayload(id: 123, role: "manager", business: business)
    lazy var userResponseObject = UserResponseObject(id: 123, firstName: "rod", lastName: "campbell", businessMemberships: [membership])
    let freshbooksVerifiedWebhookContent = FreshbooksWebhookTriggeredContent(userID: 1,
                                                                             name: "create an invoice",
                                                                             objectID: 123,
                                                                             verified: true,
                                                                             verifier: nil,
                                                                             accountID: "123")
    let freshbooksVerifyContent = FreshbooksWebhookTriggeredContent(userID: 1,
                                                                    name: "create an invoice",
                                                                    objectID: 123,
                                                                    verified: false,
                                                                    verifier: "abc",
                                                                    accountID: "123")
    let slack = SlackWebServicingMock()
    let freshbooks = FreshbooksWebServicingMock()
    let userAccessToken = "accessTokenOfUserSavedInDB"
    lazy var controller = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks)
    
    var fetchInvoiceHandler: ((String, Int, String, Request) throws -> (EventLoopFuture<FreshbooksInvoice>))? = { a, b, c, request in
        let promise = request.eventLoop.newPromise(FreshbooksInvoice.self)
        
        DispatchQueue.global().async {
            let date = Date(timeIntervalSince1970: 123)
            promise.succeed(result: WebhookControllerTests.invoice)
        }
        return promise.futureResult
    }

    
    let failSlackRequestHandler: ((Request) throws -> (EventLoopFuture<Response>))? = { request in
        let promise = request.eventLoop.newPromise(Response.self)
        DispatchQueue.global().async {
            promise.fail(error: TestingError.slackFail)
        }
        return promise.futureResult
    }
    
    override func setUp() {
        let req = Request(using: thisApp)
        let testUser = try? User(responseObject: userResponseObject, accessToken: userAccessToken).save(on: req).wait()
        let _ = try? Webhook(webhookID: 123, userID: try testUser!.requireID()).save(on: req).wait()
    }

    override func tearDown() { }
    func testSlackMessageGetsSentOnVerifiedWebhook() throws {
        let req = Request(using: thisApp)
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
    }
    
    func testFreshbooksVerificationWebhook() throws {
        let req = Request(using: thisApp)

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
    }
    
    func testFetchInvoice() throws {
        let req = Request(using: thisApp)
        let accountID = "accountID"
        let invoiceID = 123
        let accessToken = "AccessToken"
        freshbooks.fetchInvoiceHandler = fetchInvoiceHandler
        do {
            // fetch the invoice
            let invoice = try controller.getInvoice(accountID: accountID, invoiceID: invoiceID, accessToken: accessToken, on: req)
                .map({ invoice -> FreshbooksInvoice in
                    return invoice
                }).wait()
            // verify that it's what we planned to send back
            XCTAssertEqual(invoice, WebhookControllerTests.invoice)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testDeleteWebhook() throws {
        let req = Request(using: thisApp)

        guard let user = try User.find(1, on: req).wait() else {
            XCTFail("user not in the test database")
            return
        }
        freshbooks.deleteWebhookHandler = { string, request in
            XCTAssertNotNil(self.business.accountID)
            XCTAssertEqual(self.business.accountID, string)
            return request.successPromiseAfterGlobalDispatchASync()
        }

        try req.authenticate(user)

        // fetch the invoice
        _ = try controller.deleteWebhook(req).map({ response -> Response in
            print(response)
            return response
        }).wait()
    }


}

extension Request {
    fileprivate func successPromiseAfterGlobalDispatchASync() -> EventLoopFuture<Response> {
        let promise = eventLoop.newPromise(Response.self)
        DispatchQueue.global().async {
            let httpResponse = HTTPResponse(status: .ok, version: .init(major: 1, minor: 1), headers: [:], body: "soundsGood")
            let response = Response(http: httpResponse, using: self)
            promise.succeed(result: response)
        }
        return promise.futureResult
    }
}
