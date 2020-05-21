import Vapor
import Fluent

final class FreshbooksInvoice: Model, Equatable {
    static func == (lhs: FreshbooksInvoice, rhs: FreshbooksInvoice) -> Bool {
        return lhs.freshbooksID == rhs.freshbooksID // TODO upgrade to v4
    }

    static var schema: String = "https://" // TODO upgrade to v4

    required init() {
        freshbooksID = 1
        status = 1
        paymentStatus = "TODO"
        currentOrganization = "TODO"
        amount = Amount(amount: "TODO", code: "TODO")
        createdAt = Date()
    }

    var id: Int?
    var freshbooksID: Int
//    let id: Int
    let status: Int
    var userID: Int?
    let paymentStatus: String
    let currentOrganization: String
    let amount: Amount
    let createdAt: Date

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

/// Allows `Todo` to be used as a dynamic migration.
//extension FreshbooksInvoice: Migration { } // TODO upgrade to v4

/// Allows `Todo` to be encoded to and decoded from HTTP messages.
extension FreshbooksInvoice: Content { } // TODO upgrade to v4

/// Allows `Todo` to be used as a dynamic parameter in route definitions.
//extension FreshbooksInvoice: Parameter { } // TODO upgrade to v4
