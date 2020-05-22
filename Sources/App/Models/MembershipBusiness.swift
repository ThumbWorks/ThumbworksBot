//
//  File.swift
//  
//
//  Created by Roderic Campbell on 5/21/20.
//

import Vapor
import Fluent

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
        self.$membership.id = membershipID
        self.$business.id = businessID
    }
}

struct CreateMembershipBusiness: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("membershipbusiness")
                   .id()
            .field("business_id", .uuid, .required, .references("businesss", "id"))
            .field("membership_id", .uuid, .required, .references("memberships", "id"))
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
                database.schema("membershipbusiness").delete()
    }
}
