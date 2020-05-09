//
//  UserController.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Authentication


enum UserError: Error {
    case noAccessToken
    case noAccountID
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
    func ready(_ req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        do {
            return try executeWebhook(on: req)
        } catch {
            print("Not in the content params. probably just verifying")
        }
        return try verifyWebhook(on: req)
    }

    func deleteWebhook(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.requireAuthenticated(User.self)
        guard let accountID = user.accountID() else {
            throw UserError.noAccountID
        }
        return try freshbooksService.deleteWebhook(accountID: accountID, on: req)
    }


    func registerNewWebhook(_ req: Request) throws -> EventLoopFuture<Response> {
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
    private func executeWebhook(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        return try req.content.decode(WebhookTriggered.self)
            .flatMap { triggeredPayload in
                // let objectID = triggeredPayload.objectID // TODO query freshbooks for what this is
                try self.slackService.sendSlackPayload(on: req)
        }
    }

    private func verifyWebhook(on req: Request) throws ->  EventLoopFuture<HTTPStatus> {
        return User.query(on: req).all().flatMap { (users) in
            // NOTE: At this point, freshbooks is doing an unauthenticated call. We don't generally have an access token so we hack it so that the user object has one, we fetch that and send it
            guard let accessToken = users.first?.accessToken else {
                throw UserError.noAccessToken
            }
            return try self.freshbooksService.confirmWebhook(accessToken: accessToken, on: req)
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
