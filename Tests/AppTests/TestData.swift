//
//  File.swift
//  
//
//  Created by Roderic Campbell on 5/22/20.
//

import Foundation
import XCTVapor
@testable import App

struct TestData {
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

    static let fetchInvoiceHandler: ((String, Int, String, Request) throws -> (EventLoopFuture<FreshbooksInvoiceContent>))? = { a, b, c, request in
        let promise = request.eventLoop.makePromise(of: FreshbooksInvoiceContent.self)
        DispatchQueue.global().async {
            promise.succeed(TestData.invoice)
        }
        return promise.futureResult
    }
}

struct TestingDeleteWebhookRequestPayload: Codable {
    let id: Int
}
