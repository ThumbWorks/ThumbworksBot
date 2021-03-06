//
//  Webhook.swift
//  App
//
//  Created by Roderic Campbell on 5/13/20.
//

import Foundation
import Fluent
import FluentPostgresDriver   

final class Webhook: Model, Codable {
    static var schema: String = "webhooks"

    init() {}

    typealias Database = PostgresDatabase

    @ID(key: .id)
    var id: UUID?

    @Field(key: "webhookID")
    var webhookID: Int

    @Field(key: "userID")
    var userID: UUID

    init(webhookID: Int, userID: UUID) {
        self.webhookID = webhookID
        self.userID = userID
    }
}

struct CreateWebhook: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema(Webhook.schema)
                  .id()
                  .field("webhookID", .int)
                  .field("userID", .uuid)
                  .unique(on: "webhookID")
                  .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema(Webhook.schema).delete()
    }
}
