import Vapor
import Fluent

final class FreshbooksInvoice: Model, Equatable {
    static func == (lhs: FreshbooksInvoice, rhs: FreshbooksInvoice) -> Bool {
        return lhs.freshbooksID == rhs.freshbooksID // TODO upgrade to v4
    }

    static var schema: String = "https://" // TODO upgrade to v4

    required init() {
    }

   @ID(key: .id)
    var id: UUID?

    @Field(key: "freshbooksID")
    var freshbooksID: Int

    @Field(key: "status")
    var status: Int

    @Field(key: "status")
    var userID: Int?

    @Field(key: "status")
    var paymentStatus: String

    @Field(key: "status")
    var currentOrganization: String

    @Field(key: "status")
    var amount: Amount

    @Field(key: "status")
    var createdAt: Date

    struct Amount: Content, Equatable {
        let amount: String
        let code: String
    }
}

struct FreshbooksInvoiceContent: Content, Equatable {
    var id: Int?
    var freshbooksID: Int
    var status: Int
    var userID: Int?
    var paymentStatus: String
    var currentOrganization: String
    var amount: Amount
    var createdAt: Date

    struct Amount: Content, Equatable {
        let amount: String
        let code: String
    }
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, amount, userID
        case freshbooksID = "id"
        case createdAt = "created_at"
        case paymentStatus = "payment_status"
        case currentOrganization = "current_organization"
    }
}
