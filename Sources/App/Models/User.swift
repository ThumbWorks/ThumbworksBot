//
//  User.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Authentication
import FluentSQLite
final class User: SQLiteModel, Codable {
    var id: Int?
    var accessToken: String
    var freshbooksID: Int
    var firstName: String
    var lastName: String
    var businessMemberships: [MembershipPayload]
    init(responseObject: UserResponseObject, accessToken: String) {
        businessMemberships = responseObject.businessMemberships
        freshbooksID = responseObject.id
        firstName = responseObject.firstName
        lastName = responseObject.lastName
        self.accessToken = accessToken
    }

    func updateUser(responseObject: UserResponseObject, accessToken: String) {
        businessMemberships = responseObject.businessMemberships
        freshbooksID = responseObject.id
        firstName = responseObject.firstName
        lastName = responseObject.lastName
        self.accessToken = accessToken
    }
}
extension User: SessionAuthenticatable { }


/// Allows `User` to be used as a dynamic migration.
extension User: Migration { }

/// Allows `User` to be encoded to and decoded from HTTP messages.
extension User: Content { }

/// Allows `User` to be used as a dynamic parameter in route definitions.
extension User: Parameter { }

extension User {

    var webhooks: Children<User, Webhook> {
        return children(\.userID)
    }
    var invoices: Children<User, FreshbooksInvoice> {
           return children(\.userID)
    }
}
