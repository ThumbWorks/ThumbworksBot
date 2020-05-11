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

    let successSlackRequestHandler: ((Request) throws -> (EventLoopFuture<Response>))? = { request in
        let promise = request.eventLoop.newPromise(Response.self)
        DispatchQueue.global().async {
            let httpResponse = HTTPResponse(status: .ok, version: .init(major: 1, minor: 1), headers: [:], body: "soundsGood")
            let response = Response(http: httpResponse, using: request)
            promise.succeed(result: response)
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
    override func setUp() { }
    override func tearDown() { }
    func testSlackMessageGetsSentOnVerifiedWebhook() throws {
        // Set up the success case
        slack.sendSlackPayloadHandler =  successSlackRequestHandler
        let thisApp = try app(Environment(name: "test", isRelease: false))
        let req = Request(using: thisApp)
        do {
            try req.content.encode(freshbooksVerifiedWebhookContent)
        } catch {
            XCTFail(error.localizedDescription)
        }

        XCTAssertEqual(try controller.ready(req).wait(), HTTPStatus.ok)
        XCTAssertEqual(slack.sendSlackPayloadCallCount, 1)
    }

    func testFreshbooksVerificationWebhook() throws {
        // Set up the success case
        let thisApp = try app(Environment(name: "test", isRelease: false))
        let req = Request(using: thisApp)
        let business = BusinessPayload(id: 345, name: "Thumbworks", accountID: "accountID123")
        let membership = MembershipPayload(id: 123, role: "manager", business: business)
        let response = UserResponseObject(id: 123, firstName: "rod", lastName: "campbell", businessMemberships: [membership])
        _ = try User(responseObject: response, accessToken: "accessToken").save(on: req).wait()

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
        catch {
            XCTFail()
            print(error)
        }
    }
}
