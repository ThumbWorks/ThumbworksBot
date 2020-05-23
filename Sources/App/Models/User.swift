//
//  User.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Fluent


final class User: Model {
    static var schema: String = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "accessToken")
    var accessToken: String

    @Field(key: "freshbooksID")
    var freshbooksID: Int

    @Field(key: "firstName")
    var firstName: String

    @Field(key: "lastName")
    var lastName: String

    @Children(for: \.$user)
    var businessMemberships: [Membership]

    init() {}

    init(responseObject: UserResponseObject, accessToken: String) {
        // TODO add the businessMemberships to the user
//        responseObject.businessMemberships.map { Membership(membershipPayload: $0, userID: UUID()) }
        freshbooksID = responseObject.id
        firstName = responseObject.firstName
        lastName = responseObject.lastName
        self.accessToken = accessToken
    }
}

extension User {
    func addMemberships(from userResponse: UserResponseObject, on req: Request) throws -> EventLoopFuture<Void> {
        return try userResponse.businessMemberships.compactMap { membershipPayload in
            let membership = Membership(membershipPayload: membershipPayload, userID: try self.requireID())
            return membership.save(on: req.db).flatMap { _ in
                let business = Business(business: membershipPayload.business)
                return business.save(on: req.db).flatMap { _  in
                    return membership.$businesses.attach(business, on: req.db)
                }
            }
        }.flatten(on: req.eventLoop)
    }
    func updateUser(responseObject: UserResponseObject, accessToken: String) {
//        businessMemberships = responseObject.businessMemberships.map { Membership(membershipPayload: $0, userID: UUID()) }
        freshbooksID = responseObject.id
        firstName = responseObject.firstName
        lastName = responseObject.lastName
        self.accessToken = accessToken
    }
}

extension User: SessionAuthenticatable {
    var sessionID: String {
        return accessToken
    }
}

struct UserSessionAuthenticator: SessionAuthenticator {
    typealias User = App.User
    func authenticate(sessionID: String, for request: Request) -> EventLoopFuture<Void> {
        User.query(on: request.db)
            .filter(\.$accessToken, .equal, sessionID)
            .first()
            .unwrap(or: Abort(.notFound))
            .map { user in
                request.auth.login(user)
        }
    }
}

/// Allows `User` to be used as a dynamic migration.
struct CreateUser: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema(User.schema)
            .id()
            .field("accessToken", .string)
            .field("freshbooksID", .int64)
            .field("firstName", .string)
            .field("lastName", .string)
            .unique(on: "freshbooksID")
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
            database.schema(User.schema).delete()
    }
}

/// Allows `User` to be encoded to and decoded from HTTP messages.
extension User: Content { }
