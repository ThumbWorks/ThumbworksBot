//
//  SlackService.swift
//  App
//
//  Created by Roderic Campbell on 5/8/20.
//

import Vapor

/// @mockable
protocol SlackWebServicing {
    func sendSlackPayload(on req: Request) throws -> EventLoopFuture<HTTPStatus>
    var req: Request? { get set }
}

final class SlackWebService: SlackWebServicing {
    let slackURL: URL
    var req: Request?

    init(slackURL: URL) {
        self.slackURL = slackURL
    }

    func sendSlackPayload(on req: Request) throws -> EventLoopFuture<HTTPStatus> {
        return try SlackWebhookRequestPayload(text: "New invoice created").encode(for: req).flatMap { slackRequestPayload in
            return try req.client()
                .post(self.slackURL) { slackMessagePost in
                    slackMessagePost.http.body = slackRequestPayload.http.body
            }.transform(to: HTTPStatus.ok)
        }
    }
}
