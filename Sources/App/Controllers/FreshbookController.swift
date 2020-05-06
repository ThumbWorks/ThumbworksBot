//
//  FreshbookController.swift
//  App
//
//  Created by Roderic Campbell on 5/4/20.
//

import Vapor
import Leaf

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

    struct TestData: Encodable {
        let name: String
    }

    func index(_ req: Request) throws -> EventLoopFuture<View> {

        return try req.view().render("UserWebhooks", TestData(name: "roddy"))
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


    func freshbooksAuth(_ req: Request) throws -> EventLoopFuture<TokenExchangeResponse> {
        let codeContianer = try req.query.decode(AuthRequest.self)
        print("we got a code from freshbooks because someone started the oauth flow \(codeContianer.code)")
        guard let url = URL(string: "https://api.freshbooks.com/auth/oauth/token") else {
            throw FreshbooksError.invalidURL
        }

        return try TokenExchangeRequest(clientSecret: clientSecret,
                                        redirectURI: URL(string: "\(callbackHost)/freshbooks/auth"),
                                        clientID: clientID,
                                        code: codeContianer.code)
            .encode(using: req)
            .flatMap { tokenRequest -> EventLoopFuture<TokenExchangeResponse> in
                return try req.client().post(url) { request in
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
