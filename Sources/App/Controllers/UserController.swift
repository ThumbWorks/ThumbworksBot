//
//  UserController.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Authentication


struct FreshbooksWebhookResponsePayload: Codable {
    let response: FreshbooksWebhookResponseResponse

}
struct FreshbooksWebhookResponseResponse: Codable {
    let result: FreshbooksWebhookResponseResult
}
struct FreshbooksWebhookResponseResult: Codable {
    let perPage: Int
    let pages: Int
    let page: Int
    let callbacks: [FreshbooksWebhookCallbackResponse]
    enum CodingKeys: String, CodingKey {
        case perPage = "per_page"
        case pages, page
        case callbacks
    }
}

struct FreshbooksWebhookCallbackResponse: Codable {
    let callbackid: Int
    let id: Int
    let verified: Bool
    let uri: URL
    let event: String
}

struct FreshbooksGetWebhookRequestPayload: Content {
    let name: String
}
enum UserError: Error {
    case noAccessToken
    case noAccountID
}
final class UserController {

    func webhooks(_ req: Request) throws -> EventLoopFuture<View> {
        let user = try req.requireAuthenticated(User.self)
//        POST https://api.freshbooks.com/events/account/<account_id>/events/callbacks
        let membershipWithAccountID = user.businessMemberships.first { membership -> Bool in
            return membership.business.accountID != nil
        }
        guard let accountID = membershipWithAccountID?.business.accountID else {
            throw UserError.noAccountID
        }
        let url = "https://api.freshbooks.com/events/account/\(accountID)/events/callbacks"
        guard let accessToken = try req.session()["accessToken"] else {
            throw UserError.noAccessToken
        }
        return try req.client().get(url, headers: [HTTPHeaderName.accept.description: "application/json"]) { webhookRequest in

            webhookRequest.http.contentType = .json
            webhookRequest.http.headers.add(name: .accept, value: "application/json")
            webhookRequest.http.headers.add(name: "Api-Version", value: "alpha")
            webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
        }.flatMap({ response in
            response.http.contentType = .json
            return try response.content.decode(FreshbooksWebhookResponsePayload.self) // this fails
                .flatMap({ webhookResponse in
                    return try req.view().render("UserWebhooks", ["callbacks": webhookResponse.response])
                })
        })
    }
}
