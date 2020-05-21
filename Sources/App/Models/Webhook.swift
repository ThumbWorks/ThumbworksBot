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
    static var schema: String = "webhook" // TODO upgrade to v4, /shrug

    init() {
        webhookID = 1 // TODO upgrade to v4
        userID = UUID() // TODO upgrade to v4
    }

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

extension Webhook {
    // TODO remove the relationship during the upgrade
//    var user: Parent<Webhook, User> {
//        return parent(\.userID)
//    }

}
//extension Webhook: Migration {
//    func prepare(on database: Database) -> EventLoopFuture<Void> {
//
//    }
//
//    func revert(on database: Database) -> EventLoopFuture<Void> {
//
//    }
//}
