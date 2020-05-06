//
//  FreshbookController.swift
//  App
//
//  Created by Roderic Campbell on 5/4/20.
//

import Vapor
import Leaf

extension URL {
    static let freshbooksAuth = URL(string: "https://api.freshbooks.com/auth/oauth/token")!
    static let freshbooksUser = URL(string: "https://api.freshbooks.com/auth/api/v1/users/me")!
}
struct AuthRequest: Content {
    let code: String
}

struct NewWebookResponseCallback: Content {
    let event: String
    let uri: String
    let callbackID: Int
    let id: Int
    let verified: Bool
}
struct NewWebhookCallback: Content {
    let event: String
    let uri: String
}
struct CreateWebhookRequestPayload: Content {
    var callback: NewWebhookCallback
}
struct IncomingWebhookPayload: Content {
    var githubTeam: String
    var swaggerSpecURL: String
}

enum FreshbooksError: Error {
    case invalidURL
}



final class FreshbooksController {

    let callbackHost: String
    let clientSecret: String
    let clientID: String

    init(clientID: String, clientSecret: String, callbackHost: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.callbackHost = callbackHost
    }

    struct FreshbooksWebhookResponse: Encodable {
        let name: String
    }

    func index(_ req: Request) throws -> EventLoopFuture<View> {
        return try req.view().render("UserWebhooks", FreshbooksWebhookResponse(name: "roddy"))
    }

    func registerNewWebhook(_ req: Request) throws -> EventLoopFuture<Response> {
        let client = try req.client()

        let account_id = "something we haven't gotten yet"
        let callback = NewWebhookCallback(event: "invoice.create", uri: "\(callbackHost)/webhook/ready")
        let requestPayload = CreateWebhookRequestPayload(callback: callback)
        guard let url = URL(string: "https://api.freshbooks.com/events/account/\(account_id)/events/callbacks") else {
            throw FreshbooksError.invalidURL
        }


        return try requestPayload.encode(using: req).flatMap { request -> EventLoopFuture<Response> in
            let body = request.http.body
            return client.post(url, headers: [:]) { request in
                request.http.body = body
            }
        }
    }

    func webhook(_ req: Request) throws -> HTTPStatus {
        return .ok
    }

    func webhookReady(_ req: Request) throws -> HTTPStatus {
        return .ok
    }

    func accessToken(_ req: Request) throws -> HTTPStatus {
        let codeContainer = try req.query.decode(AuthRequest.self)
        print("the access token at the end of the flow is \(codeContainer.code)")
        return .ok
    }

    private func exchangeToken(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse>{
        return try TokenExchangeRequest(clientSecret: clientSecret,
                                        redirectURI: URL(string: "\(callbackHost)/freshbooks/auth"),
                                        clientID: clientID,
                                        code: code)
            .encode(using: req)
            .flatMap { tokenRequest -> EventLoopFuture<TokenExchangeResponse> in
                return try req.client().post(URL.freshbooksAuth) { request in
                    request.http.contentType = .json
                    print(tokenRequest.http.body)
                    request.http.body = tokenRequest.http.body
                }.flatMap { tokenExchangeResponse -> EventLoopFuture<TokenExchangeResponse> in
                    return try tokenExchangeResponse.content.decode(TokenExchangeResponse.self)
                }.do({ response in
                    print(response)
                })
        }
    }
    func freshbooksAuth(_ req: Request) throws -> EventLoopFuture<View> {
        let codeContainer = try req.query.decode(AuthRequest.self)
        print("we got a code from freshbooks because someone started the oauth flow \(codeContainer.code)")
        return try exchangeToken(with: codeContainer.code, on: req)
            .fetchAuthenticatedUser(on: req)
            .showUserWebhookView(on: req)
    }
}

extension EventLoopFuture where T == UserFetchResponse {
    func showUserWebhookView(on req: Request) throws -> EventLoopFuture<View> {
        flatMap { try req.view().render("UserWebhooks", $0.response) }
    }
}

extension EventLoopFuture where T == TokenExchangeResponse {
    func fetchAuthenticatedUser(on req: Request) throws ->  EventLoopFuture<UserFetchResponse> {
        flatMap { (tokenExchangeResponse) -> EventLoopFuture<UserFetchResponse> in
            try UserFetchRequest(accessToken: tokenExchangeResponse.accessToken).encode(for: req).flatMap { userFetchResponse -> EventLoopFuture<UserFetchResponse> in
                return try req.client().get(URL.freshbooksUser) { userRequest in
                    userRequest.http.contentType = .json
                    userRequest.http.headers.add(name: "Api-Version", value: "alpha")
                    userRequest.http.headers.add(name: .authorization, value: "Bearer \(tokenExchangeResponse.accessToken)")
                }.flatMap { try $0.content.decode(UserFetchResponse.self) }
            }
        }

    }
}

struct UserFetchRequest: Content {
    let accessToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct UserFetchResponse: Content {
    let response: UserResponseObject
}
struct UserResponseObject: Content {
    let id: Int
    let firstName: String
    let lastName: String
    enum CodingKeys: String, CodingKey {
           case firstName = "first_name"
           case lastName = "last_name"
           case id
    }
}

struct TokenExchangeResponse: Content {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String
    let createdAt: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case createdAt = "created_at"
    }
}

struct TokenExchangeRequest: Content {
    let grantType = "authorization_code"
    let clientSecret: String// = client_secret
    let redirectURI: URL?// = URL(string: "\(callbackHost)/freshbooks/auth")
    let clientID: String// = client_id
    var code: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientSecret = "client_secret"
        case redirectURI = "redirect_uri"
        case clientID = "client_id"
        case code = "code"
    }
}
