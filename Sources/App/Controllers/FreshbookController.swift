//
//  FreshbookController.swift
//  App
//
//  Created by Roderic Campbell on 5/4/20.
//

import Vapor
import Leaf
import Fluent

final class FreshbooksController {
    let app: Application
    let freshbooksService: FreshbooksWebServicing
    let userSessionAuthenticator: UserSessionAuthenticator
    let hostname: String
    let clientID: String
    let clientSecret: String
    init(hostname: String, clientSecret: String, clientID: String, freshbooksService: FreshbooksWebServicing, app: Application, userSessionAuthenticator: UserSessionAuthenticator) {
        self.freshbooksService = freshbooksService
        self.hostname = hostname
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.app = app
        self.userSessionAuthenticator = userSessionAuthenticator
    }

    func index(_ req: Request) throws -> EventLoopFuture<View> {
        return req.view.render("UserWebhooks")
    }

    func webhook(_ req: Request) throws -> HTTPStatus {
        return .ok
    }

    func accessToken(_ req: Request) throws -> HTTPStatus {
        let codeContainer = try req.query.decode(AuthRequest.self)
        req.session.data["accessToken"] = codeContainer.code
        return .ok
    }

    func freshbooksAuth(_ req: Request) throws -> EventLoopFuture<View> {
        let codeContainer = try req.query.decode(AuthRequest.self)
        return try freshbooksService.auth(with: codeContainer.code, on: req)
            .flatMap({ (tokenResponse) -> EventLoopFuture<View> in
            do {
                return try self.freshbooksService
                    .fetchUser(accessToken: tokenResponse.accessToken, on: req)
                    .flatMap { userResponseObject -> EventLoopFuture<Void> in
                        return User.query(on: req.db)
                            .filter(\.$freshbooksID, .equal, userResponseObject.id)
                            .first()
                            .flatMap { user  in
                                let savableUser: User
                                if let user = user {
                                    // If yes, update
                                    savableUser = user
                                    savableUser.updateUser(responseObject: userResponseObject, accessToken: tokenResponse.accessToken)
                                } else {
                                    // If no, create
                                    savableUser = User(responseObject: userResponseObject, accessToken: tokenResponse.accessToken)
                                }
                                return savableUser.save(on: req.db).flatMapThrowing { Void  in
                                    return try savableUser.addMemberships(from: userResponseObject, on: req)
                                }.flatMap { user in
                                    return self.userSessionAuthenticator.authenticate(sessionID: tokenResponse.accessToken, for: req)
                                }
                        }
                }
                .flatMap { _ in req.view.render("SetCookie") }
            } catch {
                return req.eventLoop.makeFailedFuture(error)
            }
        })
    }

    func getInvoices(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        return user.accountID(on: req)
            .unwrap(or: UserError.noAccountID)
            .flatMap { accountID in
                let payload = GetInvoicePayload(accountID: accountID,
                                                accessToken:user.accessToken,
                                                page: 1,
                                                hostname: self.hostname,
                                                clientID: self.clientID,
                                                clientSecret: self.clientSecret)
                return req.queue.dispatch(GetInvoiceJob.self, payload).transform(to: HTTPStatus.ok)
        }
    }
}
