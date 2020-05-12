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

enum WebhookError: Error {
    case webhookNotFound
    case orphanedWebhook
    case unableToParseWebhook
}


struct SlackWebhookRequestPayload: Content {
    let text: String
    let iconEmoji: String?
    init(text: String, iconEmoji: String? = nil) {
        self.text = text
        self.iconEmoji = iconEmoji
    }
    enum CodingKeys: String, CodingKey {
           case text
           case iconEmoji = "icon_emoji"
       }
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


    func registerNewWebhook(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)

        guard let accountID = user.accountID() else {
            throw UserError.noAccountID
        }

        guard let accessToken = try req.session()["accessToken"] else {
            throw UserError.noAccessToken
        }
        return try freshbooksService.registerNewWebhook(accountID: accountID, accessToken: accessToken, on: req)
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
                // let objectID = triggeredPayload.objectID // TODO query freshbooks for what this is
                try self.slackService.sendSlackPayload(on: req)
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
                return try self.freshbooksService.confirmWebhook(accessToken: user.accessToken, on: req)
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
