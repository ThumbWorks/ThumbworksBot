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

final class FreshbooksController {
    let freshbooksService: FreshbooksWebServicing
    init(freshbooksService: FreshbooksWebServicing) {
        self.freshbooksService = freshbooksService
    }

    func index(_ req: Request) throws -> EventLoopFuture<View> {
        return try req.view().render("UserWebhooks")
    }

    func webhook(_ req: Request) throws -> HTTPStatus {
        return .ok
    }

    func accessToken(_ req: Request) throws -> HTTPStatus {
        let codeContainer = try req.query.decode(AuthRequest.self)
        try req.session()["accessToken"] = codeContainer.code
        return .ok
    }

    func freshbooksAuth(_ req: Request) throws -> EventLoopFuture<View> {
        let codeContainer = try req.query.decode(AuthRequest.self)
        return try freshbooksService.auth(with: codeContainer.code, on: req).flatMap({ (tokenResponse) -> EventLoopFuture<View> in
            try req.session()["accessToken"] = tokenResponse.accessToken
            return try self.freshbooksService
                .fetchUser(accessToken: tokenResponse.accessToken, on: req)
                .queryUser(on: req)
                .showUserWebhookView(on: req)
        })
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

struct AuthRequest: Content {
    let code: String
}

struct NewWebhookCallbackRequest: Content {
    let event: String
    let uri: String
}

struct CreateWebhookRequestPayload: Content {
    var callback: NewWebhookCallbackRequest
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
