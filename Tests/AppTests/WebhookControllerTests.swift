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

extension Invoice {
    convenience init(freshbooksID: Int, status: Int, paymentStatus: String, currentOrganization: String, amount: String, amountCode: String, createdAt: Date) {
        self.init()
        self.freshbooksID = freshbooksID
        self.status = status
        self.paymentStatus = paymentStatus
        self.currentOrganization = currentOrganization
        self.amount = amount
        self.amountCode = amountCode
        self.createdAt = createdAt
        self.init()
    }
}

class WebhookControllerTests: XCTestCase {
    var application: Application! = nil

    var testUser: User?

    let slack = SlackWebServicingMock()
    let freshbooks = FreshbooksWebServicingMock()
    lazy var webhookController = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks)

    override func setUp() {
        application = Application(Environment.testing)
        try? configure(application)

        let req = Request(application: application, on: application.eventLoopGroup.next())
        testUser = User(responseObject: TestData.userResponseObject, accessToken: TestData.userAccessToken)
        testUser?.id = UUID()
        try? testUser?.save(on: req.db).wait()
        try? Business(business: TestData.business).save(on: req.db).wait()

        do {
            let _ = try Webhook(webhookID: 123, userID: try testUser!.requireID()).save(on: req.db).wait()
        } catch {
            print(error)
        }
    }

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
        freshbooks.fetchInvoiceHandler = TestData.fetchInvoiceHandler
        
        try? req.content.encode(TestData.freshbooksVerifiedWebhookContent)
        // Run the command
        XCTAssertEqual(try webhookController.ready(req).wait(), HTTPStatus.ok)
        
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
            XCTAssertEqual(token, TestData.userAccessToken)
            return request.successPromiseAfterGlobalDispatchASync()
        }

        do {
            try req.content.encode(TestData.freshbooksVerifyContent)
            let status = try webhookController.ready(req).wait()
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

    func testDeleteWebhook() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())

        freshbooks.deleteWebhookHandler = { userID, webhookID, request in
            XCTAssertNotNil(TestData.business.accountID)
            XCTAssertEqual(TestData.business.accountID, userID)
            return request.successPromiseAfterGlobalDispatchASync()
        }
        _ = try UserSessionAuthenticator().authenticate(sessionID: TestData.userAccessToken, for: req).wait()
        try req.query.encode(TestingDeleteWebhookRequestPayload(id: 123))

        // Ensure that the webhook exists before we attempt to delete it
        XCTAssertEqual(try Webhook.query(on: req.db).all().wait().count, 1)

        do {
            // Delete the webhook
            _ = try webhookController.deleteWebhook(req).wait()

            // Ensure that the webhook is out of the database
            XCTAssertEqual(try Webhook.query(on: req.db).all().wait().count, 0)
        } catch {
            XCTFail(error.localizedDescription)
        }

        XCTAssertEqual(freshbooks.deleteWebhookCallCount, 1)
    }
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
