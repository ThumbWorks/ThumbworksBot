//
//  Business.swift
//  
//
//  Created by Roderic Campbell on 5/21/20.
//

import Fluent
import Vapor

final class Business: Model {
    static var schema: String = "businesses"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "accountID")
    var accountID: String?

    @Field(key: "freshbooksID")
    var freshbooksID: Int

    @Siblings(through: MembershipBusiness.self, from: \.$business, to: \.$membership)
    var memberships: [Membership]

    init() {}
    init(business: BusinessPayload) {
        name = business.name
        accountID = business.accountID
        freshbooksID = business.id
    }
}

struct CreateBusiness: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema(Business.schema)
            .id()
            .field("name", .string)
            .field("accountID", .string)
            .field("freshbooksID", .int)
            .unique(on: "freshbooksID")
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema(Business.schema).delete()
    }
}
