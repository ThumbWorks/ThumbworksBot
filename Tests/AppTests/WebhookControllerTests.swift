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
    let freshbooks = FreshbooksWebServicingMockWithDefaultHandlers()
    lazy var webhookController = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks, clientID: "abc", clientSecret: "secret")
    lazy var deps = ApplicationDependencies(freshbooksServicing: freshbooks,
                                            slackServicing: slack,
                                            hostname: "",
                                            clientID: "'",
                                            clientSecret: "secret",
                                            databaseURLString: nil) { sessionID, request in
                                                let promise = request.eventLoop.makePromise(of: Void.self)
                                                DispatchQueue.global().async {
                                                    promise.succeed(Void())
                                                }
                                                return promise.futureResult
    }

    override func setUp() {
        application = Application(Environment.testing)
        try? configure(application, dependencies: deps)
        let req = Request(application: application, on: application.eventLoopGroup.next())
        let user = User(responseObject: TestData.userResponseObject,
                        accessToken: TestData.userAccessToken)
        testUser = user
        try? user.save(on: req.db).wait()
        guard let userID = try? user.requireID() else {
            return
        }
        let membershipPayload = MembershipPayload(id: 1234, role: "manager", business: TestData.business)
        let membership = Membership(membershipPayload: membershipPayload, userID: userID)

        _ = try? membership.save(on: req.db).flatMap { _ -> EventLoopFuture<Void> in
            let business = Business(business: membershipPayload.business)
            return business.save(on: req.db).flatMap { _  in
                return membership.$businesses.attach(business, on: req.db)
            }
        }.wait()

        do {
            let _ = try Webhook(webhookID: 123, userID: userID).save(on: req.db).wait()
        } catch {
            print(error)
        }
    }

    override func tearDown() {

        // Order matters when deleting all of these things.
        print("start the cleanup")
        let req = Request(application: application, on: application.eventLoopGroup.next())

        print("delete all webhooks")
        // remove all webhooks
        try? Webhook.query(on: req.db).all().wait().forEach { object in
            try? object.delete(on: req.db).wait()
        }

        print("delete all MembershipBusiness")
        // remove all businesses
        try? MembershipBusiness.query(on: req.db).all().wait().forEach { object in
            try? object.delete(on: req.db).wait()
        }

        print("delete all Business")
        // remove all businesses
        try? Business.query(on: req.db).all().wait().forEach { object in
            try? object.delete(on: req.db).wait()
        }

        print("delete all Membership")
        // remove all businesses
        try? Membership.query(on: req.db).all().wait().forEach { object in
            try? object.delete(on: req.db).wait()
        }

        print("delete all users")
        // remove all users
        try? User.query(on: req.db).all().wait().forEach { object in
            try? object.delete(on: req.db).wait()
        }
    }

    func testExecuteWebhookNewPayment() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())
        let executeWebhookPayload = FreshbooksWebhookTriggeredContent(freshbooksUserID: 123,
                                                                      name: WebhookType.paymentCreate.rawValue,
                                                                      objectID: 123,
                                                                      verified: true,
                                                                      verifier: nil,
                                                                      accountID: TestData.business.accountID ?? "booo")
        try req.content.encode(executeWebhookPayload)
        // setup fetch payment handler
        freshbooks.fetchPaymentHandler = { accountID, paymentID, accessToken, request in
            return request.successPromisePaymentContent()
        }

        // setup slack handler
        slack.sendSlackPayloadHandler = { string, emoji, request in
            XCTAssertEqual(string, "New payment landed: 123.00 USD")
            return request.successPromiseClientResponse()
        }

        _ = try webhookController.ready(req).wait()
        XCTAssertEqual(slack.sendSlackPayloadCallCount, 1)
    }
    
    func testExecuteWebhookNewInvoice() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())
        var expectedEmoji: Emoji? = Emoji.apple
        var expectedSlackPayloadString: String = ""
        
        // set custom slack handler
        slack.sendSlackPayloadHandler = { string, emoji, request in
            expectedEmoji = emoji
            expectedSlackPayloadString = string
            return request.successPromiseClientResponse()
        }
        
        try? req.content.encode(TestData.invoiceCreateWebhookContent)
        // Run the command
        XCTAssertEqual(try webhookController.ready(req).wait(), HTTPStatus.ok)
        
        // validate the results
        XCTAssertEqual(expectedEmoji, Emoji.uber)
        XCTAssertEqual(expectedSlackPayloadString, "New invoice created to Uber Technologies, Inc, for 123 USD")
        
        XCTAssertEqual(slack.sendSlackPayloadCallCount, 1)
        XCTAssertEqual(freshbooks.fetchInvoiceCallCount, 1)

    }

    func testExecuteWebhookNewClient() throws {
          let req = Request(application: application, on: application.eventLoopGroup.next())
          var expectedEmoji: Emoji? = Emoji.apple
          var expectedSlackPayloadString: String = ""

          // set custom slack handler
          slack.sendSlackPayloadHandler = { string, emoji, request in
              expectedEmoji = emoji
              expectedSlackPayloadString = string
              return request.successPromiseClientResponse()
          }


        freshbooks.fetchClientHandler = { _, _, _, request in
            return request.successPromiseClientContentResponse()
        }
        try? req.content.encode(TestData.clientCreateWebhookContent)
          // Run the command
          XCTAssertEqual(try webhookController.ready(req).wait(), HTTPStatus.ok)

          // validate the results
          XCTAssertEqual(expectedEmoji, Emoji.apple)
          XCTAssertEqual(expectedSlackPayloadString, "New client added: Apple")

          XCTAssertEqual(slack.sendSlackPayloadCallCount, 1)
          XCTAssertEqual(freshbooks.fetchClientCallCount, 1)

      }
    
    func testFreshbooksVerificationWebhook() throws {
        let req = Request(application: application, on: application.eventLoopGroup.next())

        // Verify that we are able to fetch the user from the database and the access token set is being sent to confirm webhook
        freshbooks.confirmWebhookHandler = { token, request in
            XCTAssertEqual(token, TestData.userAccessToken)
            return request.successPromiseVoid()
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
        print(req.auth.login(testUser!))
        freshbooks.deleteWebhookHandler = { userID, webhookID, request in
            XCTAssertNotNil(TestData.business.accountID)
            XCTAssertEqual(TestData.business.accountID, userID)
            return request.successPromiseVoid()
        }
        let userAuthenticator = UserSessionAuthenticator(authenticationClosure: deps.authenticationClosure)
        _ = try userAuthenticator.authenticate(sessionID: TestData.userAccessToken, for: req).wait()
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
