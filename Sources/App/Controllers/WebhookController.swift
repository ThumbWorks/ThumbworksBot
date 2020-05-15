//
//  UserController.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Authentication


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
        return try req.content.decode(FreshbooksWebhookTriggeredContent.self)
            .flatMap { triggeredPayload in
                if let _  = triggeredPayload.verifier {
                    return try self.verifyWebhook(webhookID: triggeredPayload.objectID, on: req).transform(to: .ok)
                }
                return try self.executeWebhook(on: req).transform(to: .ok)
        }
    }

    func deleteWebhook(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.requireAuthenticated(User.self)
        guard let accountID = user.accountID() else {
            throw UserError.noAccountID
        }
        return try freshbooksService.deleteWebhook(accountID: accountID, on: req)
    }

    func getInvoices(_ req: Request) throws -> EventLoopFuture<[FreshbooksInvoice]> {
        let user = try req.requireAuthenticated(User.self)
        guard let accountID = user.accountID() else {
            throw UserError.noAccountID
        }
        guard let accessToken = try req.session()["accessToken"] else {
            throw UserError.noAccessToken
        }
        return FreshbooksInvoice.query(on: req).all().flatMap({ (invoices) in
            print("totalInvoices \(invoices.count)")
            let total = invoices.reduce(0.0, { x, invoiceAmount in
                guard let amount = Double(invoiceAmount.amount.amount) else {
                    return 0
                }
                return x + amount
            })
            print(total)
            return try self.freshbooksService
                .allInvoices(accountID: accountID, accessToken: accessToken, page: 1, on: req)
                .do({ invoices in
                    
                    let total = invoices.reduce(0.0, { x, invoice in
                        guard let amount = Double(invoice.amount.amount) else {
                            return 0
                        }
                        return x + amount
                    })
                    print(total)
            })
        })
    }

    func getInvoice(accountID: String, invoiceID: Int, accessToken: String, on req: Request) throws -> EventLoopFuture<FreshbooksInvoice> {
        return try freshbooksService.fetchInvoice(accountID: accountID, invoiceID: invoiceID, accessToken: accessToken, req: req)
    }

    func registerNewWebhook(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)

        guard let accountID = user.accountID() else {
            throw UserError.noAccountID
        }

        guard let accessToken = try req.session()["accessToken"] else {
            throw UserError.noAccessToken
        }
        return try freshbooksService.registerNewWebhook(accountID: accountID, accessToken: accessToken, on: req).flatMap({ webhookPayload in
            let newWebhook = Webhook(webhookID: webhookPayload.response.result.callback.callbackid, userID: try user.requireID())
            return newWebhook.save(on: req).transform(to: .ok)
        })
    }

    /// Show the website describing a user. The website will AJAX to get the it's webhooks
    func webhooks(_ req: Request) throws -> EventLoopFuture<View> {
        return try req.view().render("UserWebhooks")
    }

    /// JSON describing the user's webhooks
    func allWebhooks(_ req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult> {
        let user = try req.requireAuthenticated(User.self)
        let membershipWithAccountID = user.businessMemberships.first { membership -> Bool in
            return membership.business.accountID != nil
        }
        guard let accountID = membershipWithAccountID?.business.accountID else {
            throw UserError.noAccountID
        }
        guard let accessToken = try req.session()["accessToken"] else {
            throw UserError.noAccessToken
        }
        return try freshbooksService.fetchWebhooks(accountID: accountID, accessToken: accessToken, req: req)
    }

}

extension WebhookController {
    private func executeWebhook(on req: Request) throws ->  EventLoopFuture<Response> {
        return try req.content.decode(FreshbooksWebhookTriggeredContent.self)
            .flatMap { triggeredPayload in
                return User.find(triggeredPayload.userID, on: req).flatMap { user in
                    guard let user = user else {
                        throw WebhookError.orphanedWebhook
                    }

                    guard let accountID = user.accountID() else {
                        throw UserError.noAccountID
                    }
                    let objectID = triggeredPayload.objectID
                    return try self.getInvoice(accountID: accountID,
                                               invoiceID: objectID,
                                               accessToken: user.accessToken,
                                               on: req)
                        .flatMap({ invoice in
                            let text = "New invoice created to \(invoice.currentOrganization), for \(invoice.amount.amount) \(invoice.amount.code)"
                            let emoji = Emoji(rawValue: invoice.currentOrganization)
                            return try self.slackService.sendSlackPayload(text: text, with:emoji, on: req)
                        })
                }
        }
    }

    private func verifyWebhook(webhookID: Int, on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        return Webhook.query(on: req).filter(\.webhookID == webhookID).first().flatMap { webhook in
            guard let webhook = webhook else {
                throw WebhookError.webhookNotFound
            }
            return User.find(webhook.userID, on: req).flatMap { user in
                guard let user = user else {
                    throw WebhookError.orphanedWebhook
                }
                return try self.freshbooksService
                    .confirmWebhook(accessToken: user.accessToken, on: req)
                    .transform(to: .ok)
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
