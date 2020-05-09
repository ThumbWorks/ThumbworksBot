//
//  UserController.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Authentication


struct FreshbooksWebhookResponsePayload: Codable, Content {
    let response: FreshbooksWebhookResponseResponse

}
struct FreshbooksWebhookResponseResponse: Codable, Content {
    let result: FreshbooksWebhookResponseResult
}

struct DeleteWebhookRequestPayload: Codable {
    let id: Int
}
struct FreshbooksWebhookResponseResult: Codable, Content {
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

struct FreshbooksWebhookCallbackResponse: Codable, Content {
    let callbackid: Int
    let verified: Bool
    let uri: String
    let event: String
}

struct FreshbooksGetWebhookRequestPayload: Content {
    let name: String
}
enum UserError: Error {
    case noAccessToken
    case noAccountID
}

//user_id=214214&name=callback.verify&verifier=xYfXk5imkxAmS3k8JnDnz4sGD4Pk62WASm&object_id=778573&account_id=xazq5&system=https%3A%2F%2Fthumbworks.freshbooks.com)
struct FreshbooksReadyPayload: Codable {
//    let userID: Int
    let name: String
    let verifier: String
    let objectID: Int
    let accountID: String
    let system: String
    enum CodingKeys: String, CodingKey {
//        case userID = "user_id"
        case name, verifier, system
        case accountID = "account_id"
        case objectID = "object_id"
    }
}

struct FreshbookConfirmReadyPayload: Content {
    let callback: FreshbooksCallback
}

struct FreshbooksCallback: Content {
    let callbackID: Int
    let verifier: String
    enum CodingKeys: String, CodingKey {
            case verifier
            case callbackID = "callback_id"
    }
}

//user_id=214214&name=callback.verify&verifier=xf8pxDkZfSXuak7S4qaGQBvxArpMvqR&object_id=778599&account_id=xazq5&system=https%3A%2F%2Fthumbworks.freshbooks.com)

struct WebhookTriggered: Content {
    let userID: Int
    let name: String
    let objectID: String
    let accountID: String
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case objectID = "object_id"
        case accountID = "account_id"
        case name
    }
}

struct SlackWebhookRequestPayload: Content {
    let text: String
    let iconEmoji: String?
    init(text: String, iconEmoji: String? = nil) {
        self.text = text
        self.iconEmoji = iconEmoji
    }
    enum CodingKeys: String, CodingKey {
           case text
           case iconEmoji = "icon_emoji"
       }
}

final class WebhookController {
    let hostName: String
    let slackURL: URL
    init(hostName: String, slackURL: URL) {
        self.hostName = hostName
        self.slackURL = slackURL
    }

    // The webhook receiver.
    // Original Documentation: https://www.freshbooks.com/api/webhooks
    // Freshbooks will call this method with the webhook POST.
    // If they're looking to verify the webhook we take one route with a `FreshbooksReadyPayload` payload.
    // If they are sending a webhook call, we get a `WebhookTriggered` payload.
    // We only know what type this is based on the payload
    //
    // The ready payload looks like this:
    //
    // In order to verify the payload reciept we need to send the following
    //        PUT https://api.freshbooks.com/events/account/<account_id>/events/callbacks/<callback_id>
    //        {
    //            "callback": {
    //                "callback_id": 2001,
    //                "verifier": "scADVVi5QuKuj5qTjVkbJNYQe7V7USpGd"
    //            }
    //        }
    //
    // The webhook payload looks like this:
    // http://your_server.com/webhooks/ready?name=invoice.create&object_id=1234567&account_id=6BApk&user_id=1
    func ready(_ req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        do {
            return try executeWebhook(on: req)
        } catch {
            print("Not in the content params. probably just verifying")
        }
        return try verifyWebhook(on: req)
    }

    func deleteWebhook(_ req: Request) throws -> EventLoopFuture<Response> {
           let user = try req.requireAuthenticated(User.self)
           let client = try req.client()
           guard let accountID = user.accountID() else {
               throw UserError.noAccountID
           }

           let deletePayload = try req.query.decode(DeleteWebhookRequestPayload.self)

           guard let url = URL(string: "https://api.freshbooks.com/events/account/\(accountID)/events/callbacks/\(deletePayload.id)") else {
               throw FreshbooksError.invalidURL
           }

           guard let accessToken = try req.session()["accessToken"] else {
               throw UserError.noAccessToken
           }

           return client.delete(url, headers: [HTTPHeaderName.accept.description: "application/json"]) { webhookRequest in
               webhookRequest.http.contentType = .json
               webhookRequest.http.headers.add(name: .accept, value: "application/json")
               webhookRequest.http.headers.add(name: "Api-Version", value: "alpha")
               webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
           }
       }

       func registerNewWebhook(_ req: Request) throws -> EventLoopFuture<Response> {
           let user = try req.requireAuthenticated(User.self)
           let client = try req.client()

           guard let accountID = user.accountID() else {
               throw UserError.noAccountID
           }
           let callback = NewWebhookCallback(event: "invoice.create", uri: "\(hostName)/webhooks/ready")
           let requestPayload = CreateWebhookRequestPayload(callback: callback)
           guard let url = URL(string: "https://api.freshbooks.com/events/account/\(accountID)/events/callbacks") else {
               throw FreshbooksError.invalidURL
           }

           guard let accessToken = try req.session()["accessToken"] else {
               throw UserError.noAccessToken
           }

           return try requestPayload.encode(using: req).flatMap { request -> EventLoopFuture<Response> in
               let body = request.http.body
               return client.post(url, headers: [HTTPHeaderName.accept.description: "application/json"]) { webhookRequest in
                   webhookRequest.http.body = body
                   webhookRequest.http.contentType = .json
                   webhookRequest.http.headers.add(name: .accept, value: "application/json")
                   webhookRequest.http.headers.add(name: "Api-Version", value: "alpha")
                   webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
               }
           }
       }

    /// Show the website describing a user. The website will AJAX to get the it's webhooks
    func webhooks(_ req: Request) throws -> EventLoopFuture<View> {
        return try req.view().render("UserWebhooks")
    }

    /// JSON describing the user's webhooks
    func allWebhooks(_ req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult> {
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
            return try response.content.decode(FreshbooksWebhookResponsePayload.self)
                .flatMap({ payload in
                    req.future().map { payload.response.result }
                })
        })
    }
}

private extension WebhookController {
    private func sendSlackPayload(on req: Request) throws -> EventLoopFuture<HTTPStatus> {
        return try SlackWebhookRequestPayload(text: "New invoice created").encode(for: req).flatMap { slackRequestPayload in
            return try req.client()
                .post(self.slackURL) { slackMessagePost in
                    slackMessagePost.http.body = slackRequestPayload.http.body
            }.transform(to: HTTPStatus.ok)
        }
    }

    private func executeWebhook(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        return try req.content.decode(WebhookTriggered.self)
            .flatMap { triggeredPayload in
                // let objectID = triggeredPayload.objectID // TODO query freshbooks for what this is
                try self.sendSlackPayload(on: req)
        }
    }

    private func verifyWebhook(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        return try req.content.decode(FreshbooksReadyPayload.self).flatMap { payload in
            return User.query(on: req).all().flatMap { (users) in
                // NOTE: At this point, freshbooks is doing an unauthenticated call. We don't generally have an access token so we hack it so that the user object has one, we fetch that and send it
                guard let accessToken = users.first?.accessToken else {
                    throw UserError.noAccessToken
                }

                print("ready payload \(payload)")
                let client = try req.client()

                guard let url = URL(string: "https://api.freshbooks.com/events/account/\(payload.accountID)/events/callbacks/\(payload.objectID)") else {
                    throw FreshbooksError.invalidURL
                }

                return try FreshbookConfirmReadyPayload(callback: FreshbooksCallback(callbackID: payload.objectID, verifier: payload.verifier)).encode(for: req).flatMap { confirmedReadyPayload -> EventLoopFuture<HTTPStatus> in
                    return client.put(url) { webhookRequest in
                        webhookRequest.http.body = confirmedReadyPayload.http.body
                        webhookRequest.http.contentType = .json
                        webhookRequest.http.headers.add(name: .accept, value: "application/json")
                        webhookRequest.http.headers.add(name: "Api-Version", value: "alpha")
                        webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
                    }.transform(to: HTTPStatus.ok   )
                }
            }
        }
    }
}

extension User {
    func accountID() -> String? {
        return businessMemberships.first { membership -> Bool in
            return membership.business.accountID != nil
            }?.business.accountID
    }
}
