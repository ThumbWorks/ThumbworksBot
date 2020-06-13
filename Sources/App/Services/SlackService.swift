//
//  SlackService.swift
//  App
//
//  Created by Roderic Campbell on 5/8/20.
//

import Vapor

public enum Emoji: String {
    case uber = "Uber Technologies, Inc"
    case lohi = "Lohi Labs"
    case apple = "Apple"

    var symbol: String {
        get {
            switch self {
            case .uber:
                return ":uber:"
            case .lohi:
                return ":walmart:"
            case .apple:
                return ":apple:"
            }
        }
    }
}
/// @mockable
public protocol SlackWebServicing {
    func sendSlackPayload(text: String, with emoji: Emoji?, on req: Request) throws -> EventLoopFuture<ClientResponse>
}

public final class SlackWebService: SlackWebServicing {
    let slackURL: URI

    public init(slackURL: URI) {
        self.slackURL = slackURL
    }

    public func sendSlackPayload(text: String, with emoji: Emoji?, on req: Request) throws -> EventLoopFuture<ClientResponse> {
        return req.client.post(self.slackURL) { request in
            try request.content.encode(SlackWebhookRequestPayload(text: text, iconEmoji: emoji?.symbol))
        }.map { $0 }
    }
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
