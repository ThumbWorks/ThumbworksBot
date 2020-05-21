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
        return try userResponse.businessMemberships.map { membershipPayload ->  EventLoopFuture<Void> in
            let membership = Membership(membershipPayload: membershipPayload, userID: try self.requireID())
            return membership.save(on: req.db)
            // TODO need to a) iterate over all of these and b) save the businesses
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

//extension User: ModelSessionAuthenticatable {
//
//}

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
        database.schema("users")
            .id()
            .field("accessToken", .string)
            .field("freshbooksID", .int64)
            .field("firstName", .string)
            .field("lastName", .string)
            .unique(on: "freshbooksID")
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
            database.schema("users").delete()
    }
}

/// Allows `User` to be encoded to and decoded from HTTP messages.
extension User: Content { }

/// Allows `User` to be used as a dynamic parameter in route definitions.
//extension User: Parameter { } // TODO upgrade to v4

extension User {

    // TODO upgrade to v4
//    var webhooks: Children<User, Webhook> {
//        return children(\.userID)
//    }
//    var invoices: Children<User, FreshbooksInvoice> {
//           return children(\.userID)
//    }
}


final class MembershipBusiness: Model {
    // Name of the table or collection.
    static let schema: String = "membership_business"

    // Unique identifier for this pivot.
    @ID(key: .id)
    var id: UUID?

    // Reference to the Tag this pivot relates.
    @Parent(key: "membership_id")
    var membership: Membership

    // Reference to the Star this pivot relates.
    @Parent(key: "business_id")
    var business: Business

    // Creates a new, empty pivot.
    init() {}

    // Creates a new pivot with all properties set.
    init(membershipID: UUID, businessID: UUID) {
        self.membership.id = membershipID
        self.business.id = businessID
    }
}

struct CreateMembershipBusiness: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("membershipbusiness")
                   .id()
//            .field("business", .custom(Business.self))
//            .field("membership", .custom(Membership.self))
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
                database.schema("membershipbusiness").delete()

    }
}

final class Membership: Model {
    static var schema: String = "memberships"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "role")
    var role: String

//    @Siblings(key: "business")
//    var business: Business

    @Field(key: "freshbooksID")
    var freshbooksID: Int

    @Parent(key: "user_id")
    var user: User

    init() {}

    init(membershipPayload: MembershipPayload, userID: UUID) {
//        business = Business(business: membershipPayload.business) // TODO I need to create these
        role = membershipPayload.role
        self.$user.id = userID
    }
}

struct CreateMembership: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("memberships")
            .id()
            .field("role", .string)
            .field("freshbooksID", .int)
            .field("user_id", .uuid, .references("users", "id"))
            .unique(on: "freshbooksID")
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("memberships").delete()
    }
}

final class Business: Model {
    static var schema: String = "businesses"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "accountID")
    var accountID: String

    @Field(key: "freshbooksID")
    var freshbooksID: Int

    init() {}
    init(business: BusinessPayload) {
        name = business.name
        accountID = business.accountID ?? "no accountID"
        freshbooksID = business.id
    }
}

struct CreateBusiness: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("businesses")
            .id()
            .field("name", .string)
            .field("accountID", .string)
            .field("freshbooksID", .int)
            .unique(on: "freshbooksID")
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("businesses").delete()
    }
}
