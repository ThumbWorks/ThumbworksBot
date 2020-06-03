//
//  Membership.swift
//  
//
//  Created by Roderic Campbell on 5/21/20.
//

import Vapor
import Fluent

final class Membership: Model {
    static var schema: String = "memberships"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "role")
    var role: String

    @Field(key: "freshbooksID")
    var freshbooksID: Int

    @Parent(key: "user_id")
    var user: User

    @Siblings(through: MembershipBusiness.self, from: \.$membership, to: \.$business)
    var businesses: [Business]
    
    init() {}

    init(membershipPayload: MembershipPayload, userID: UUID) {
        role = membershipPayload.role
        self.$user.id = userID
    }
}

struct CreateMembership: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema(Membership.schema)
            .id()
            .field("role", .string)
            .field("freshbooksID", .int)
            .field("user_id", .uuid, .references(User.schema, "id"))
            .unique(on: "freshbooksID")
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema(Membership.schema).delete()
    }
}
