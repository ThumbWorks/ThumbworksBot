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
                                           amount: Amount(amount: "123", code: "USD"))
    let business = BusinessPayload(id: 345, name: "Thumbworks", accountID: "accountID123")
    lazy var membership = MembershipPayload(id: 123, role: "manager", business: business)
    lazy var response = UserResponseObject(id: 123, firstName: "rod", lastName: "campbell", businessMemberships: [membership])
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
    lazy var controller = WebhookController(hostName: "localhost", slackService: slack, freshbooksService: freshbooks)
    
    let confirmWebhookRequestHandler: ((String, Request) throws -> (EventLoopFuture<HTTPStatus>))? = { token, request in
        let promise = request.eventLoop.newPromise(Response.self)
        DispatchQueue.global().async {
            let httpResponse = HTTPResponse(status: .ok, version: .init(major: 1, minor: 1), headers: [:], body: "soundsGood")
            let response = Response(http: httpResponse, using: request)
            promise.succeed(result: response)
        }
        return promise.futureResult.transform(to: .ok)
    }
    
    let successSlackRequestHandler: ((String, Emoji?, Request) throws -> (EventLoopFuture<Response>))? = { string, emoji, request in
        let promise = request.eventLoop.newPromise(Response.self)
        DispatchQueue.global().async {
            let httpResponse = HTTPResponse(status: .ok, version: .init(major: 1, minor: 1), headers: [:], body: "soundsGood")
            let response = Response(http: httpResponse, using: request)
            promise.succeed(result: response)
        }
        return promise.futureResult
    }
    
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
        
        let testUser = try? User(responseObject: response, accessToken: "accessToken").save(on: req).wait()
        let _ = try? Webhook(webhookID: 123, userID: try testUser!.requireID()).save(on: req).wait()
    }
    override func tearDown() { }
    func testSlackMessageGetsSentOnVerifiedWebhook() throws {
        let req = Request(using: thisApp)
        // Set up the success case
        //        slack.sendSlackPayloadHandler =  successSlackRequestHandler
        
        var expectedEmoji: Emoji? = Emoji.apple
        var expectedSlackPayloadString: String = "shouldChange"
        
        // set custom slack handler
        slack.sendSlackPayloadHandler = { string, emoji, request in
            expectedEmoji = emoji
            expectedSlackPayloadString = string
            let promise = request.eventLoop.newPromise(Response.self)
            DispatchQueue.global().async {
                let httpResponse = HTTPResponse(status: .ok, version: .init(major: 1, minor: 1), headers: [:], body: "soundsGood")
                let response = Response(http: httpResponse, using: request)
                promise.succeed(result: response)
            }
            return promise.futureResult
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
        freshbooks.confirmWebhookHandler = confirmWebhookRequestHandler
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
}
