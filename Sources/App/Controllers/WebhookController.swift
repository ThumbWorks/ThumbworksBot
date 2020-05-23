//
//  UserController.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Fluent
enum UserError: Error {
    case noUserWithThatAccessToken
    case noAccessToken
    case noAccountID

}
enum InvoiceError: Error {
    case notParsed
}

enum WebhookError: Error {
    case webhookNotFound
    case orphanedWebhook
    case unableToParseWebhook
}

final public  class WebhookController {
    let freshbooksService: FreshbooksWebServicing
    let hostName: String
    let slackService: SlackWebServicing
    init(hostName: String, slackService: SlackWebServicing, freshbooksService: FreshbooksWebServicing) {
        self.hostName = hostName
        self.slackService = slackService
        self.freshbooksService = freshbooksService
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
    public func ready(_ req: Request) throws ->  EventLoopFuture<HTTPStatus> {
//        return req.client.post(self.slackURL) { request in
//                  try request.content.encode(SlackWebhookRequestPayload(text: text, iconEmoji: emoji?.symbol))
//              }.map { $0 }

        let triggeredPayload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        if let _  = triggeredPayload.verifier {
            return try self.verifyWebhook(webhookID: triggeredPayload.objectID, on: req).transform(to: .ok)
        }
        return try self.executeWebhook(on: req).transform(to: .ok)
    }

    private struct DeleteWebhookRequestPayload: Codable {
        let id: Int
    }

    func deleteWebhook(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)

        return user.accountID(on: req)
            .unwrap(or: UserError.noAccountID)
            .flatMap { accountID in
                do {
                    let webhookID = try req.query.decode(DeleteWebhookRequestPayload.self).id
                    return try self.freshbooksService.deleteWebhook(accountID: accountID, webhookID: webhookID, on: req)
                        .flatMap({ response in
                            Webhook.query(on: req.db)
                                .filter(\.$webhookID, .equal, webhookID)
                                .first()
                                .unwrap(or: WebhookError.webhookNotFound)
                                .flatMap { webhook in
                                    webhook.delete(on: req.db)
                            }
                        }).transform(to: .ok)
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


    func getInvoice(accountID: String, invoiceID: Int, accessToken: String, on req: Request) throws -> EventLoopFuture<FreshbooksInvoiceContent> {
        return try freshbooksService.fetchInvoice(accountID: accountID, invoiceID: invoiceID, accessToken: accessToken, req: req)
    }

    func registerNewWebhook(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)

        return user.accountID(on: req)
            .unwrap(or: UserError.noAccountID)
            .flatMap { accountID in
                do {
                    guard let accessToken = req.session.data["accessToken"] else {
                        throw UserError.noAccessToken
                    }

                    let webhookPayload = try self.freshbooksService.registerNewWebhook(accountID: accountID, accessToken: accessToken, on: req)
                    return webhookPayload.flatMap { payload in
                        do {
                            let callbackID = payload.response.result.callback.callbackid
                            return Webhook(webhookID: callbackID, userID: try user.requireID())
                                .save(on: req.db)
                                .map { _ in HTTPStatus.ok }
                        } catch {
                            return req.eventLoop.makeFailedFuture(error)
                        }
                    }
                } catch {
                    return req.eventLoop.makeFailedFuture(error)
                }
        }
    }

    /// Show the website describing a user. The website will AJAX to get the it's webhooks
    func webhooks(_ req: Request) throws -> EventLoopFuture<View> {
        return req.view.render("UserWebhooks")
    }

    /// JSON describing the user's webhooks
    func allWebhooks(_ req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult> {
        let user = try req.auth.require(User.self)
        let accessToken = user.accessToken
        return Business
            .query(on: req.db)
            .filter(\.$accountID, .notEqual, nil)
            .first()
            .unwrap(or: Abort(.notFound))
            .flatMap { business in
                guard let accountID = business.accountID else {
                    return req.eventLoop.makeFailedFuture(Abort(.notFound))
                }
                do {
                    return try self.freshbooksService.fetchWebhooks(accountID: accountID,
                                                                    accessToken: accessToken,
                                                                    req: req)
                } catch {
                    return req.eventLoop.makeFailedFuture(error)
                }
        }
    }

}

extension WebhookController {
    private func executeWebhook(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        let triggeredPayload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        return User.query(on: req.db).all().flatMap { allUsers in
            let user = allUsers.first
//        }
            //        return User.find(triggeredPayload.freshbooksUserID, on: req.db).flatMap { user in
            do {
                guard let user = user else {
                    throw WebhookError.orphanedWebhook
                }
                return user.accountID(on: req)
                    .unwrap(or: UserError.noAccountID)
                    .flatMap { accountID in
                        do {
                            let objectID = triggeredPayload.objectID
                            return try self.getInvoice(accountID: accountID,
                                                       invoiceID: objectID,
                                                       accessToken: user.accessToken,
                                                       on: req)
                                .flatMap({ invoice in
                                    let text = "New invoice created to \(invoice.currentOrganization), for \(invoice.amount.amount) \(invoice.amount.code)"
                                    let emoji = Emoji(rawValue: invoice.currentOrganization)
                                    do {
                                        return try self.slackService.sendSlackPayload(text: text, with:emoji, on: req).transform(to: .ok)
                                    }
                                    catch {
                                        return req.eventLoop.makeFailedFuture(error)
                                    }
                                })
                        } catch {
                            return req.eventLoop.makeFailedFuture(error)
                        }
                }
            } catch {
                return req.eventLoop.makeFailedFuture(error)
            }
        }
    }

    private func verifyWebhook(webhookID: Int, on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        //        return Webhook.query(on: req.db).filter(\.webhookID == webhookID).first().flatMap { webhook in
        // TODO need to figure out how to filter queries
        return Webhook
            .query(on: req.db)
            .filter(\.$webhookID, .equal, webhookID)
            .first()
            .flatMap { webhook in
            do {
                guard let webhook = webhook else {
                    throw WebhookError.webhookNotFound
                }
                return User.find(webhook.userID, on: req.db).flatMap { user in
                    do {
                        guard let user = user else {
                            throw WebhookError.orphanedWebhook
                        }

                        return try self.freshbooksService
                            .confirmWebhook(accessToken: user.accessToken, on: req)
                            .transform(to: .ok)
                    } catch {
                        return req.eventLoop.makeFailedFuture(error)
                    }
                }
            } catch {
                return req.eventLoop.makeFailedFuture(error)
            }
        }
    }
}
extension User {
    func accountID(on req: Request) -> EventLoopFuture<String?> {
        return Business
            .query(on: req.db)
            .filter(\.$accountID, .notEqual, nil)
            .first()
            .unwrap(or: Abort(.notFound)).map { business in
                return business.accountID
        }
    }
}
