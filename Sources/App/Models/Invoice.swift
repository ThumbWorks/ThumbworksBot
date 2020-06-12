import Vapor
import Fluent

final class Invoice: Model, Equatable, Content {
    static func == (lhs: Invoice, rhs: Invoice) -> Bool {
        return lhs.freshbooksID == rhs.freshbooksID // TODO upgrade to v4
    }

    static var schema: String = "invoices"

    required init() {
    }

   @ID(key: .id)
    var id: UUID?

    @Field(key: "freshbooksID")
    var freshbooksID: Int

    @Field(key: "status")
    var status: Int

    @Field(key: "userID")
    var userID: Int?

    @Field(key: "paymentStatus")
    var paymentStatus: String

    @Field(key: "currentOrganization")
    var currentOrganization: String

    @Field(key: "createdAt")
    var createdAt: Date

    @Field(key: "amount")
    var amount: String

    @Field(key: "amountCode")
    var amountCode: String

}

struct CreateInvoice: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema(Invoice.schema)
            .id()
            .field("freshbooksID", .int)
            .field("status", .int)
            .field("userID", .int)
            .field("paymentStatus", .string)
            .field("currentOrganization", .string)
            .field("amountCode", .string)
            .field("amount", .string)
            .field("createdAt", .date)
            .unique(on: "freshbooksID")
            .create()
      }

    func revert(on database: Database) -> EventLoopFuture<Void> {
           database.schema(Invoice.schema).delete()
       }
}
