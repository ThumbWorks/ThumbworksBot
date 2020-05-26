//
//  File.swift
//  
//
//  Created by Roderic Campbell on 5/22/20.
//

import Foundation
import XCTVapor
@testable import App


class FreshbooksWebServicingMockWithDefaultHandlers: FreshbooksWebServicingMock {
    override var fetchInvoiceHandler: ((String, Int, String, Request) throws -> (EventLoopFuture<FreshbooksInvoiceContent>))? {
        get {
            return { _, _, _, request in
                let promise = request.eventLoop.makePromise(of: FreshbooksInvoiceContent.self)
                DispatchQueue.global().async {
                    promise.succeed(TestData.invoice)
                }
                return promise.futureResult
            }
        }
        set {
        }
    }

    override var fetchUserHandler: ((String, Request) throws -> (EventLoopFuture<UserFetchResponsePayload>))? {
        get {

            return  { _, request in
                let promise = request.eventLoop.makePromise(of: UserFetchResponsePayload.self)
                DispatchQueue.global().async {
                    promise.succeed(TestData.userFetchResponsePayload)
                }
                return promise.futureResult
            }
        }
        set {}
    }

    override var authHandler: ((String, Request) throws -> (EventLoopFuture<TokenExchangeResponse>))? {
        get {
            return { _, request in
                let promise = request.eventLoop.makePromise(of: TokenExchangeResponse.self)
                DispatchQueue.global().async {
                    promise.succeed(TestData.tokenExchangeResponse)
                }
                return promise.futureResult
            }
        }
        set {}
    }

    override var registerNewWebhookHandler: ((String, String, Request) throws -> (EventLoopFuture<NewWebhookPayload>))? {
        get {

            return { _, _, request in
                let promise = request.eventLoop.makePromise(of: NewWebhookPayload.self)
                DispatchQueue.global().async {
                    promise.succeed(TestData.newWebhookResponse)
                }
                return promise.futureResult
            }
        }
        set {}
    }
}

struct TestData {
    static let authRequest = AuthRequest(code: "dummyCode")
    static let invoice = FreshbooksInvoiceContent(freshbooksID: 1,
                                                  status: 2,
                                                  paymentStatus: "unpaid",
                                                  currentOrganization: Emoji.uber.rawValue,
                                                  amount: FreshbooksInvoiceContent.Amount(amount: "123", code: "USD"),
                                                  createdAt: Date())
    static let business = BusinessPayload(id: 345, name: "Thumbworks", accountID: "businessAccountID")
    static let membership = MembershipPayload(id: 123, role: "manager", business: TestData.business)
    static let userResponseObject = UserResponseObject(id: 123, firstName: "rod", lastName: "campbell", businessMemberships: [TestData.membership])
    static let freshbooksVerifiedWebhookContent = FreshbooksWebhookTriggeredContent(freshbooksUserID: 1,
                                                                                    name: "create an invoice",
                                                                                    objectID: 123,
                                                                                    verified: true,
                                                                                    verifier: nil,
                                                                                    accountID: "123")
    static let freshbooksVerifyContent = FreshbooksWebhookTriggeredContent(freshbooksUserID: 1,
                                                                           name: "create an invoice",
                                                                           objectID: 123,
                                                                           verified: false,
                                                                           verifier: "abc",
                                                                           accountID: "123")
    static let userAccessToken = "accessTokenOfUserSavedInDB"



    static let newWebhookResponse: NewWebhookPayload = {
        let callback = NewWebhookPayload.NewWebhookPayloadResult.NewWebhookPayloadCallback(callbackid: 123)
        let result = NewWebhookPayload.NewWebhookPayloadResult(callback: callback)
        let response = NewWebhookPayload.NewWebhookPayloadResponse(result: result)
        return NewWebhookPayload(response: response)
    }()

    static let tokenExchangeResponse = TokenExchangeResponse(accessToken: userAccessToken,
                                                             tokenType: "",
                                                             expiresIn: 0,
                                                             refreshToken: "",
                                                             scope: "",
                                                             createdAt: 0)
    static let userFetchResponsePayload = UserFetchResponsePayload(response: TestData.userResponseObject)
}

public extension Request {
    func successPromiseAfterGlobalDispatchASync() -> EventLoopFuture<ClientResponse> {
        let promise = eventLoop.makePromise(of: ClientResponse.self)
        DispatchQueue.global().async {
            let response = ClientResponse(status: .ok, headers: [:], body: nil)
            promise.succeed(response)
        }
        return promise.futureResult
    }
}

struct TestingDeleteWebhookRequestPayload: Codable {
    let id: Int
}
