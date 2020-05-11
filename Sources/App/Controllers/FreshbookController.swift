//
//  FreshbookController.swift
//  App
//
//  Created by Roderic Campbell on 5/4/20.
//

import Vapor
import Leaf
import FluentSQLite
import AuthenticationServices
extension URL {
    static let freshbooksAuth = URL(string: "https://api.freshbooks.com/auth/oauth/token")!
    static let freshbooksUser = URL(string: "https://api.freshbooks.com/auth/api/v1/users/me")!
}


// Errors
enum FreshbooksError: Error {
    case invalidURL
    case noAccessTokenFound
    case noVerifierAttribute
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

    func index(_ req: Request) throws -> EventLoopFuture<View> {
        return try req.view().render("UserWebhooks")
    }

    func webhook(_ req: Request) throws -> HTTPStatus {
        return .ok
    }

    func accessToken(_ req: Request) throws -> HTTPStatus {
        let codeContainer = try req.query.decode(AuthRequest.self)
        print("the access token at the end of the flow is \(codeContainer.code)")
        try req.session()["accessToken"] = codeContainer.code
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
                }
        }
    }
    func freshbooksAuth(_ req: Request) throws -> EventLoopFuture<View> {
        let codeContainer = try req.query.decode(AuthRequest.self)
        print("we got a code from freshbooks because someone started the oauth flow \(codeContainer.code)")
        return try exchangeToken(with: codeContainer.code, on: req)
            .generateGetUserRequest(on: req)
            .queryUser(on: req)
            .showUserWebhookView(on: req)
    }
}

extension EventLoopFuture where T == UserFetchResponsePayload {


    func queryUser(on req: Request) throws -> EventLoopFuture<User> {
        flatMap { userResponse -> EventLoopFuture<User> in
            return User.query(on: req).filter(\.freshbooksID == userResponse.response.id).first().flatMap { user in
                let savableUser: User
                if let user = user {
                    // If yes, update
                    savableUser = user
                    savableUser.updateUser(responseObject: userResponse.response, accessToken: try req.session()["accessToken"] ?? "")
                } else {
                    // If no, create
                    savableUser = User(responseObject: userResponse.response, accessToken: try req.session()["accessToken"] ?? "")
                }
                // try req.authenticate(savableUser)
                try req.authenticateSession(savableUser)
                return savableUser.save(on: req)
            }
        }
    }
}

extension EventLoopFuture where T == User {
    func showUserWebhookView(on req: Request) throws -> EventLoopFuture<View> {
        return flatMap { _ in
            return try req.view().render("SetCookie")
        }
    }
}

extension EventLoopFuture where T == TokenExchangeResponse {
    func generateGetUserRequest(on req: Request) throws ->  EventLoopFuture<UserFetchResponsePayload> {
        flatMap { (tokenExchangeResponse) -> EventLoopFuture<UserFetchResponsePayload> in
            try req.session()["accessToken"] = tokenExchangeResponse.accessToken

            return try UserFetchRequest(accessToken: tokenExchangeResponse.accessToken).encode(for: req)
                .flatMap { userFetchResponse -> EventLoopFuture<UserFetchResponsePayload> in
                    return try req.client().get(URL.freshbooksUser) { userRequest in
                        userRequest.http.contentType = .json
                        userRequest.http.headers.add(name: "Api-Version", value: "alpha")
                        userRequest.http.headers.add(name: .authorization, value: "Bearer \(tokenExchangeResponse.accessToken)")
                    }.flatMap { userFetchResponse in
                        let userFetchResponseObject = try userFetchResponse.content.decode(UserFetchResponsePayload.self)
                        return userFetchResponseObject
                    }
            }
        }
    }
}

// Mark network models

struct UserFetchRequest: Content {
    let accessToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct UserFetchResponsePayload: Content {
    let response: UserResponseObject
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

struct UserResponseObject: Content {
    let id: Int
    let firstName: String
    let lastName: String
    let businessMemberships: [MembershipPayload]
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case id
        case businessMemberships = "business_memberships"
    }
}

struct MembershipPayload: Content {
    let id: Int
    let role: String
    let business: BusinessPayload
}

struct BusinessPayload: Content {
    let id: Int
    let name: String
    let accountID: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case accountID = "account_id"
    }
}
