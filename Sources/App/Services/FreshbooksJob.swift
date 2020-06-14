//
//  FreshbooksJob.swift
//  App
//
//  Created by Roderic Campbell on 5/14/20.
//

import Foundation
import Vapor
import Queues

// MARK: - Register all of the webhooks
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
        return service.registerNewWebhook(credentials: .init(accountID: payload.accountID, accessToken: user.accessToken),
                                          type: payload.type,
                                          with: context.application.client)
            .flatMap {
                do {
                    return Webhook(webhookID: $0.callbackid, userID: try user.requireID())
                        .save(on: context.application.db)
                } catch {
                    return context.eventLoop.makeFailedFuture(error)
                }
        }
    }
    static func serializePayload(_ payload: WebhookType) throws -> [UInt8] {
        return Array(payload.rawValue.utf8)
    }

    static func parsePayload(_ bytes: [UInt8]) throws -> WebhookType {
        return WebhookType(rawValue: String(decoding: bytes, as: UTF8.self)) ?? .unknown
    }
}

// MARK: - Fetch all of the invoices
struct GetInvoicePayload: Codable {
    let accountID: String
    let accessToken: String
    let page: Int
    let hostname: String
    let clientID: String
    let clientSecret: String
}

struct GetInvoiceJob: Job {
    typealias Payload = GetInvoicePayload

    func dequeue(_ context: QueueContext, _ payload: Payload) -> EventLoopFuture<Void> {
        let service = FreshbooksWebservice(hostname: payload.hostname,
                                           clientID: payload.clientID,
                                           clientSecret: payload.clientSecret)
        return service.fetchInvoices(credentials: .init(accountID: payload.accountID, accessToken: payload.accessToken),
                                     page: payload.page,
                                     with: context.application.client)
            .flatMapThrowing { metaData in
                let currentPage = metaData.page
                let totalPages = metaData.pages
                if currentPage < totalPages {
                    print("fetch \(currentPage + 1)")
                    let payload = GetInvoicePayload(accountID: payload.accountID,
                                                    accessToken:payload.accessToken,
                                                    page: currentPage + 1,
                                                    hostname: payload.hostname,
                                                    clientID: payload.clientID,
                                                    clientSecret: payload.clientSecret)
                    _ = context.application.queues.queue.dispatch(GetInvoiceJob.self, payload)
                }
                // save these invoices
                metaData.invoices.forEach { content in
                    _ = content.invoice().save(on: context.application.db)
                }
        }
    }
}
