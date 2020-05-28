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
    init(freshbooksService: FreshbooksWebServicing, app: Application) {
        self.freshbooksService = freshbooksService
        self.app = app
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
            req.session.data["accessToken"] = tokenResponse.accessToken
            do {
                return try self.freshbooksService
                    .fetchUser(accessToken: tokenResponse.accessToken, on: req)
                    .flatMap { userResponse -> EventLoopFuture<Void> in
                        print(userResponse)
                        let userID = userResponse.response.id
                        return User.query(on: req.db)
                            .filter(\.$freshbooksID, .equal, userID)
                            .first()
                            .flatMap { user  in
                                let savableUser: User
                                if let user = user {
                                    // If yes, update
                                    savableUser = user
                                    savableUser.updateUser(responseObject: userResponse.response, accessToken: tokenResponse.accessToken)
                                } else {
                                    // If no, create
                                    savableUser = User(responseObject: userResponse.response, accessToken: tokenResponse.accessToken)
                                }
                                return savableUser.save(on: req.db).flatMapThrowing { Void  in
                                    return try savableUser.addMemberships(from: userResponse.response, on: req)
                                }.flatMap { user in
                                    return UserSessionAuthenticator().authenticate(sessionID: tokenResponse.accessToken, for: req)
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
                do {
                    guard let accessToken = req.session.data["accessToken"] else {
                        throw UserError.noAccessToken
                    }
                    
                    let saveIncrementalsClosure: ([FreshbooksInvoiceContent]) -> () = { invoiceContents in
                        invoiceContents.forEach { content in
                            print("saving \(content.freshbooksID) from \(content.createdAt)")
                            let invoice = content.invoice()
                            _ = invoice.save(on: req.db)
                        }
                    }
                    let recursiveResults = try self.recursiveFetchInvoices(page: 1,
                                                                           accountID: accountID,
                                                                           accessToken: accessToken,
                                                                           onIncremental: saveIncrementalsClosure,
                                                                           on: req)
                    return recursiveResults
                        .transform(to: HTTPStatus.ok)
                } catch {
                    return req.eventLoop.makeFailedFuture(error)
                }
        }
    }

    private func recursiveFetchInvoices(page: Int, accountID: String, accessToken: String, onIncremental: @escaping ([FreshbooksInvoiceContent]) -> (), on req: Request) throws -> EventLoopFuture<[FreshbooksInvoiceContent]>  {
        return try self.freshbooksService
            .fetchInvoices(accountID: accountID, accessToken: accessToken, page: page, on: req).flatMap { metaData in
                let theseInvoices = req.eventLoop.makeSucceededFuture(metaData.invoices)
                theseInvoices.whenSuccess { onIncremental($0) }
                do {
                    if metaData.pages > page {
                        return try self.recursiveFetchInvoices(page: page + 1, accountID: accountID, accessToken: accessToken, onIncremental: onIncremental, on: req)
                    }
                    return theseInvoices
                }  catch {
                    return req.eventLoop.makeFailedFuture(error)
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

public struct UserFetchResponsePayload: Content {
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
