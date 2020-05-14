//
//  Webhook.swift
//  App
//
//  Created by Roderic Campbell on 5/13/20.
//

import Foundation
import FluentSQLite

final class Webhook: SQLiteModel, Codable {
    var id: Int?
    var webhookID: Int
    var userID: Int

    init(webhookID: Int, userID: Int) {
        self.webhookID = webhookID
        self.userID = userID
    }
}

extension Webhook {
    var user: Parent<Webhook, User> {
        return parent(\.userID)
    }

}
extension Webhook: Migration { }
