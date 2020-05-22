//
//  Webhook.swift
//  App
//
//  Created by Roderic Campbell on 5/13/20.
//

import Foundation
import Fluent
import FluentSQL
import FluentSQLiteDriver   

final class Webhook: Model, Codable {
    static var schema: String = "webhooks" // TODO upgrade to v4, /shrug

    init() {}

    typealias Database = SQLiteDatabase

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
        database.schema("webhooks")
                  .id()
                  .field("webhookID", .int)
                  .field("userID", .uuid)
                  .unique(on: "webhookID")
                  .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("webhooks").delete()
    }
}
