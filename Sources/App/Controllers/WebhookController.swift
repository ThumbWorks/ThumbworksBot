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
    case businessNotFound
    case unknown(String)
}

final public  class WebhookController {
    let freshbooksService: FreshbooksWebServicing
    let hostName: String
    let slackService: SlackWebServicing
    let clientID: String
    let clientSecret: String
    init(hostName: String, slackService: SlackWebServicing, freshbooksService: FreshbooksWebServicing, clientID: String, clientSecret: String) {
        self.hostName = hostName
        self.slackService = slackService
        self.freshbooksService = freshbooksService
        self.clientID = clientID
        self.clientSecret = clientSecret
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

    func registerNewWebhook(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)

        return user.accountID(on: req)
            .unwrap(or: UserError.noAccountID)
            .flatMap { accountID in
                do {
                    guard let accessToken = req.session.data["accessToken"] else {
                        throw UserError.noAccessToken
                    }

                    _ = WebhookType.allCases.forEach { type in
                        print("Queuing request to create \(type)")
                        _ = req.queue.dispatch(RegisterWebhookJob.self,
                                               .init(accountID: accountID,
                                                     accessToken: accessToken,
                                                     type: type,
                                                     hostName: self.hostName,
                                                     clientID: self.clientID,
                                                     clientSecret: self.clientSecret,
                                                     user: user)
                        )
                    }
                    return req.eventLoop.makeSucceededFuture(.ok)

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
    func allWebhooks(_ req: Request) throws -> EventLoopFuture<WebhookResponseResult> {
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
    private func getBusiness(with accountID: String, on req: Request) -> EventLoopFuture<Business> {
        Business.query(on: req.db)
        .filter(\.$accountID, .equal, accountID)
        .with(\.$memberships, { $0.with(\.$user) })
        .first()
        .unwrap(or: WebhookError.businessNotFound)
    }

    private func sendToSlack(text: String, emoji: Emoji?, on req: Request) -> EventLoopFuture<HTTPStatus> {
        do {
            return try self.slackService.sendSlackPayload(text: text, with:emoji, on: req).transform(to: .ok)
        }
        catch {
            return req.eventLoop.makeFailedFuture(error)
        }
    }

    private func handleInvoiceCreate(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        let triggeredPayload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        return getBusiness(with: triggeredPayload.accountID, on: req)
            .map { $0.memberships.first?.user }
            .unwrap(or: WebhookError.orphanedWebhook)
            .flatMap { user  in
                return user.accountID(on: req)
                    .unwrap(or: UserError.noAccountID)
                    .flatMap { accountID in
                        do {
                            return try self.freshbooksService.fetchInvoice(accountID: accountID, invoiceID: triggeredPayload.objectID, accessToken: user.accessToken, req: req)
                                // map it to a string
                                .map { self.newInvoiceSlackPayload(from: $0) }
                                // send it to the service
                                .flatMap { self.sendToSlack(text: $0, emoji: $1, on: req) }
                        } catch {
                            return req.eventLoop.makeFailedFuture(error)
                        }
                }
        }
    }

    private func handleInvoicePayment(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        let triggeredPayload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        return getBusiness(with: triggeredPayload.accountID, on: req)
            .map { $0.memberships.first?.user}
            .unwrap(or: WebhookError.orphanedWebhook)
            .flatMap { user  in
                return user.accountID(on: req)
                    .unwrap(or: UserError.noAccountID)
                    .flatMap { accountID in
                        do {
                            let objectID = triggeredPayload.objectID
                            return try self.freshbooksService.fetchPayment(accountID: accountID, paymentID: objectID, accessToken: user.accessToken, req: req)
                                .map { self.newPaymentSlackPayload(from: $0) }
                                .flatMap { self.sendToSlack(text: $0, emoji: nil, on: req) }
                        } catch {
                            return req.eventLoop.makeFailedFuture(error)
                        }
                }
        }
    }

    private func handleClientCreate(on req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let triggeredPayload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        return getBusiness(with: triggeredPayload.accountID, on: req)
                   .map { $0.memberships.first?.user}
                   .unwrap(or: WebhookError.orphanedWebhook)
                   .flatMap { user  in
                       return user.accountID(on: req)
                           .unwrap(or: UserError.noAccountID)
                           .flatMap { accountID in
                               do {
                                let objectID = triggeredPayload.objectID
                                return try self.freshbooksService.fetchClient(accountID: accountID, clientID: objectID, accessToken: user.accessToken, req: req)
                                    .map { self.newClientSlackPayload(from: $0) }
                                    .flatMap { self.sendToSlack(text: $0, emoji: $1, on: req) }
                               } catch {
                                   return req.eventLoop.makeFailedFuture(error)
                               }
                       }
               }
    }
    private func executeWebhook(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        let triggeredPayload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        let type = WebhookType(rawValue: triggeredPayload.name)
        switch type {
        case .invoiceCreate:
            return try handleInvoiceCreate(on: req)
        case .paymentCreate:
            return try handleInvoicePayment(on: req)
        case .clientCreate:
            return try handleClientCreate(on: req)

        default:
            let error = WebhookError.unknown("unimplemented freshbooks event handler")
            return req.eventLoop.makeFailedFuture(error)
        }
    }

    private func verifyWebhook(webhookID: Int, on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        return Webhook
            .query(on: req.db)
            .filter(\.$webhookID, .equal, webhookID)
            .first()
            .unwrap(or: WebhookError.webhookNotFound)
            .flatMap { User.find($0.userID, on: req.db) }
            .unwrap(or: WebhookError.orphanedWebhook)
            .flatMap { user in
                do {
                    return try self.freshbooksService
                        .confirmWebhook(accessToken: user.accessToken, on: req)
                        .transform(to: .ok)
                } catch {
                    return req.eventLoop.makeFailedFuture(error)
                }
        }
    }
}

// MARK: - Slack Payload Generators
extension WebhookController {
    private func newInvoiceSlackPayload(from content: InvoiceContent) -> (String, Emoji?) {
        return ("New invoice created to \(content.currentOrganization), for \(content.amount.amount) \(content.amount.code)",
            Emoji(rawValue: content.currentOrganization))
    }

    private func newPaymentSlackPayload(from content: PaymentContent) -> String {
        return ("New payment landed: \(content.amount.amount) \(content.amount.code)")
    }

    private func newClientSlackPayload(from content: ClientContent) -> (String, Emoji?) {
        return ("New client added: \(content.organization)", Emoji(rawValue: content.organization))
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

import Queues

struct RegisterWebhookPayload: Codable {
    let accountID: String
    let accessToken: String
    let type: WebhookType
    let hostName: String
    let clientID: String
    let clientSecret: String
    let user: User
}

struct RegisterWebhookJob: Job {
    static var schema: String = "_job"

    typealias Payload = RegisterWebhookPayload
    func dequeue(_ context: QueueContext, _ payload: Payload) -> EventLoopFuture<Void> {
        let service = FreshbooksWebservice(hostname: payload.hostName,
                                           clientID: payload.clientID,
                                           clientSecret: payload.clientSecret)
        let user = payload.user
        do {
            return try service.registerNewWebhook(accountID: payload.accountID,
                                                  accessToken: payload.accessToken,
                                                  type: payload.type,
                                                  with: context.application.client)
                .flatMap({ callback -> EventLoopFuture<Void> in
                    do {
                        let callbackID = callback.callbackid
                        return Webhook(webhookID: callbackID, userID: try user.requireID())
                            .save(on: context.application.db)
                    } catch {
                        return context.eventLoop.makeFailedFuture(error)
                    }
                })
        } catch {
            return context.eventLoop.makeFailedFuture(error)
        }
    }

    static func serializePayload(_ payload: WebhookType) throws -> [UInt8] {
        return Array(payload.rawValue.utf8)
    }

    static func parsePayload(_ bytes: [UInt8]) throws -> WebhookType {
        return WebhookType(rawValue: String(decoding: bytes, as: UTF8.self)) ?? .unknown
    }
}
