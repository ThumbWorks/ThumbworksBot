//
//  FreshbooksService.swift
//  App
//
//  Created by Roderic Campbell on 5/8/20.
//

import Vapor

/// @mockable
protocol FreshbooksWebServicing {
    func deleteWebhook(accountID: String, on req: Request) throws -> EventLoopFuture<Response>
    func registerNewWebhook(accountID: String, accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus>
    func fetchWebhooks(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult>
    func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus>
}

final class FreshbooksWebservice: FreshbooksWebServicing {
    let hostname: String

    init(hostname: String) {
        self.hostname = hostname
    }

    func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let client = try req.client()
        return try req.content.decode(FreshbooksWebhookTriggeredContent.self).flatMap { payload in

            guard let url = URL(string: "https://api.freshbooks.com/events/account/\(payload.accountID)/events/callbacks/\(payload.objectID)") else {
                throw FreshbooksError.invalidURL
            }
            guard let verifier = payload.verifier else {
                throw FreshbooksError.noVerifierAttribute
            }
            let callback = FreshbooksCallback(callbackID: payload.objectID, verifier: verifier)
            return try FreshbookConfirmReadyPayload(callback: callback)
                .encode(for: req)
                .flatMap { confirmedReadyPayload -> EventLoopFuture<HTTPStatus> in
                    return client.put(url) { webhookRequest in
                        webhookRequest.http.body = confirmedReadyPayload.http.body
                        webhookRequest.http.contentType = .json
                        webhookRequest.http.headers.add(name: .accept, value: "application/json")
                        webhookRequest.http.headers.add(name: "Api-Version", value: "alpha")
                        webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
                    }.transform(to: HTTPStatus.ok)
            }
        }
    }

    func deleteWebhook(accountID: String, on req: Request) throws -> EventLoopFuture<Response> {
        let client = try req.client()
        guard let accessToken = try req.session()["accessToken"] else {
            throw UserError.noAccessToken
        }
        let deletePayload = try req.query.decode(DeleteWebhookRequestPayload.self)

        guard let url = URL(string: "https://api.freshbooks.com/events/account/\(accountID)/events/callbacks/\(deletePayload.id)") else {
            throw FreshbooksError.invalidURL
        }
        return client.delete(url, headers: [HTTPHeaderName.accept.description: "application/json"]) { webhookRequest in
            webhookRequest.http.contentType = .json
            webhookRequest.http.headers.add(name: .accept, value: "application/json")
            webhookRequest.http.headers.add(name: "Api-Version", value: "alpha")
            webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
        }
    }

    func registerNewWebhook(accountID: String, accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus> {
          let callback = NewWebhookCallbackRequest(event: "invoice.create", uri: "\(hostname)/webhooks/ready")

          let requestPayload = CreateWebhookRequestPayload(callback: callback)
          guard let url = URL(string: "https://api.freshbooks.com/events/account/\(accountID)/events/callbacks") else {
              throw FreshbooksError.invalidURL
          }

        return try requestPayload.encode(using: req).flatMap { request in
            let body = request.http.body
            let client = try req.client()
            return client.post(url) { webhookRequest in
                webhookRequest.http.body = body
                webhookRequest.http.contentType = .json
                webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
            }.flatMap({ (response)  in
                // for whatever reason, couldn't parse the content properly, reverting to the old way
                guard let data = response.http.body.data,
                    let json = try? JSONSerialization.jsonObject(with: data, options: []),
                    let dict = json as? [String: Any],
                    let response = dict["response"] as? [String: Any],
                    let result = response["result"] as? [String: Any],
                    let callback = result["callback"] as? [String: Any],
                    let webhookID = callback["callbackid"] as? Int else {
                        throw WebhookError.unableToParseWebhook
                }
                let user = try req.requireAuthenticated(User.self)
                let newWebhook = Webhook(webhookID: webhookID, userID: try user.requireID())
                return newWebhook.save(on: req).transform(to: .ok)
            })
        }
    }

    func fetchWebhooks(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult> {
        let url = "https://api.freshbooks.com/events/account/\(accountID)/events/callbacks"
        return try req.client().get(url) { webhookRequest in
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


struct FreshbookConfirmReadyPayload: Content {
    let callback: FreshbooksCallback
}

struct FreshbooksCallback: Content {
    let callbackID: Int
    let verifier: String
    enum CodingKeys: String, CodingKey {
        case verifier
        case callbackID = "callbackid"
    }
}

//user_id=214214&name=callback.verify&verifier=xf8pxDkZfSXuak7S4qaGQBvxArpMvqR&object_id=778599&account_id=xazq5&system=https%3A%2F%2Fthumbworks.freshbooks.com)

struct FreshbooksWebhookTriggeredContent: Content {
    let userID: Int
    let name: String
    let objectID: Int
    let verified: Bool?
    let verifier: String?
    let accountID: String
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case objectID = "object_id"
        case accountID = "account_id"
        case verifier, verified, name
    }
}

private struct FreshbooksWebhookResponsePayload: Codable, Content {
    let response: FreshbooksWebhookResponseResponse

}
private struct FreshbooksWebhookResponseResponse: Codable, Content {
    let result: FreshbooksWebhookResponseResult
}

private struct DeleteWebhookRequestPayload: Codable {
    let id: Int
}

public struct FreshbooksWebhookResponseResult: Codable, Content {
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

public struct FreshbooksWebhookCallbackResponse: Codable, Content {
    let callbackid: Int
    let verified: Bool
    let uri: String
    let event: String
}

