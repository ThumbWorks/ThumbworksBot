//
//  File.swift
//  
//
//  Created by Roderic Campbell on 6/9/20.
//

import Vapor


public struct NewWebhookPayload: Content {
    let response: NewWebhookPayloadResponse
    struct NewWebhookPayloadResponse: Content {
        let result: NewWebhookPayloadResult
    }
    struct NewWebhookPayloadResult: Content {
        let callback: NewWebhookPayloadCallback
        struct NewWebhookPayloadCallback: Content {
            let callbackid: Int
        }
    }
}

struct FreshbookConfirmReadyPayload: Content {
    let callback: FreshbooksCallback
}

struct FreshbooksCallback: Content {
    let callbackID: Int
    let verifier: String
    enum CodingKeys: String, CodingKey {
        case verifier
        case callbackID = "callbackid"
    }
}

//user_id=214214&name=callback.verify&verifier=xf8pxDkZfSXuak7S4qaGQBvxArpMvqR&object_id=778599&account_id=xazq5&system=https%3A%2F%2Fthumbworks.freshbooks.com)

struct FreshbooksWebhookTriggeredContent: Content {
    let freshbooksUserID: Int
    let name: String
    let objectID: Int
    let verified: Bool?
    let verifier: String?
    let accountID: String
    enum CodingKeys: String, CodingKey {
        case freshbooksUserID = "user_id"
        case objectID = "object_id"
        case accountID = "account_id"
        case verifier, verified, name
    }
}

struct FreshbooksWebhookResponsePayload: Codable, Content {
    let response: FreshbooksWebhookResponseResponse

}

struct FreshbooksWebhookResponseResponse: Codable, Content {
    let result: FreshbooksWebhookResponseResult
}

public struct FreshbooksWebhookResponseResult: Codable, Content {
    let perPage: Int
    let pages: Int
    let page: Int
    let callbacks: [FreshbooksWebhookCallbackResponse]
    enum CodingKeys: String, CodingKey {
        case perPage = "per_page"
        case pages, page
        case callbacks
    }
}

public struct FreshbooksWebhookCallbackResponse: Codable, Content {
    let callbackid: Int
    let verified: Bool
    let uri: String
    let event: String
}


struct InvoicePackage: Content {
    let response: InvoiceResponse
    struct InvoiceResponse: Content {
        let result: InvoiceContainer
        struct InvoiceContainer: Content {
            let invoice: FreshbooksInvoiceContent
        }
    }
}

public struct PaymentPackage: Content { // public for now
    let response: PaymentResult
    struct PaymentResult: Content {
        // Response is getting parsed.
        let result: PaymentContentWrapper
        struct PaymentContentWrapper: Content {
            let payment: PaymentContent
        }
        enum CodingKeys: String, CodingKey {
            case result = "result"
        }
    }
}

struct ErrorResponse: Content {
    let response: ErrorResponseErrors
    struct ErrorResponseErrors: Content {
        let errors: [ErrorContent]
    }
    struct ErrorContent: Content {
        let errno: Int
        let field: String
        let message: String
        let object: String
        let value: String
    }
}

public struct PaymentContent: Content, Equatable {

    var accountingSystemID: String
    var updated: Date //"2016-09-28 21:00:46"
    var invoiceID: Int
    var amount: Amount
    var clientID: Int
    var visState: Int
    var logID: Int
    var note: String
//    var date: Date //"2013-12-10"
    var freshbooksID: Int

    struct Amount: Content, Equatable {
        let amount: String
        let code: String
    }
    enum CodingKeys: String, CodingKey {
        case amount, updated, note//, date
        case accountingSystemID = "accounting_systemid"
        case freshbooksID = "id"
        case clientID = "clientid"
        case visState = "vis_state"
        case invoiceID = "invoiceid"
        case logID = "logid"
    }
}

struct InvoicesPackage: Content {
    let response: InvoicesResult

    struct InvoicesResult: Content {
        let result: InvoicesMetaDataContent
    }
}
public struct InvoicesMetaDataContent: Content {
    let pages: Int
    let page: Int
    let invoices: [FreshbooksInvoiceContent]
}

public struct TokenExchangeResponse: Content {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String
    let createdAt: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case createdAt = "created_at"
    }
}

struct TokenExchangeRequest: Content {
    let grantType = "authorization_code"
    let clientSecret: String// = client_secret
    let redirectURI: URL?
    let clientID: String// = client_id
    var code: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientSecret = "client_secret"
        case redirectURI = "redirect_uri"
        case clientID = "client_id"
        case code = "code"
    }
}

// Errors
enum FreshbooksError: AbortError {
    var status: HTTPResponseStatus {
        switch self {

        case .invalidURL:
            return .notFound
        case .invoiceNotFound:
            return .notFound
        case .noAccessTokenFound:
            return .unauthorized
        case .noVerifierAttribute:
            return .badRequest
        case .unableToParseWebhookObject:
            return .unprocessableEntity
        }
    }

    case invalidURL
    case invoiceNotFound
    case noAccessTokenFound
    case noVerifierAttribute
    case unableToParseWebhookObject
    var reason: String {
        switch self {
        case .invalidURL:
            return "Invalid URL requested"
        case .invoiceNotFound:
            return "Invoice not Found"
        case .noAccessTokenFound:
            return "Not access token found"
        case .noVerifierAttribute:
            return "No verifier"
        case .unableToParseWebhookObject:
            return "Unable to parse Webhook"
        }
    }
}


public enum FreshbooksObjectType: String {
    case invoice
    case payment
    case category
    case expense
    case item
    case project
    case service
    case recurring
    case timeEntry

    func getURI(accountID: String) -> URI {
        switch self {
        case .invoice:
            return URI.freshbooksInvoicesURL(accountID: accountID, page: nil)
        default:
            return URI.freshbooksInvoicesURL(accountID: "abc", page: nil)
        }
    }
}

public enum WebhookType: String, CaseIterable, Codable {
    case unknown
    case all
    case category
    case categoryCreate = "category.create"
    case categoryDelete = "category.delete"
    case categoryUpdate = "category.update"
    case client
    case clientCreate = "client.create"
    case clientDelete = "client.delete"
    case clientUpdate = "client.update"
    case estimate
    case estimateCreate = "estimate.create"
    case estimateDelete = "estimate.delete"
    case estimateSendByEmail = "estimate.sendByEmail"
    case estimateUpdate = "estimate.update"
    case expense
    case expenceCreate = "expense.create"
    case expenceDelete = "expense.delete"
    case expenceUpdate = "expense.update"
    case invoice
    case invoiceCreate = "invoice.create"
    case invoiceDelete = "invoice.delete"
    case invoiceSendByEmail = "invoice.sendByEmail"
    case invoiceUpdate = "invoice.update"
    case item
    case itemCreate = "item.create"
    case itemDelete = "item.delete"
    case itemUpdate = "item.update"
    case payment
    case paymentCreate = "payment.create"
    case paymentDelete = "payment.delete"
    case paymentUpdate = "payment.update"
    case project
    case projectCreate = "project.create"
    case projectDelete = "project.delete"
    case projectUpdate = "project.update"
    case recurring
    case recurringCreate = "recurring.create"
    case recurrintDelete = "recurring.delete"
    case recurringUpdte = "recurring.update"
    case  service
    case serviceCreate = "service.create"
    case serviceDelete = "service.delete"
    case serviceUpdate = "service.update"
    case time_entry
    case timeEntryCreate = "time_entry.create"
    case timeEntryDelete = "time_entry.delete"
    case timeEntryUpdate = "time_entry.update"
}


/// MARK: User Fetch Models

struct UserFetchRequest: Content {
    let accessToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

public struct UserFetchResponsePayload: Content {
    let response: UserResponseObject
}

struct AuthRequest: Content {
    let code: String
}

struct NewWebhookCallbackRequest: Content {
    let event: WebhookType
    let uri: String
}

struct CreateWebhookRequestPayload: Content {
    var callback: NewWebhookCallbackRequest
}

public struct UserResponseObject: Content {
    let id: Int
    let firstName: String
    let lastName: String
    let businessMemberships: [MembershipPayload]
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case id
        case businessMemberships = "business_memberships"
    }
}

struct MembershipPayload: Content {

    let id: Int
    let role: String
    let business: BusinessPayload
}

struct BusinessPayload: Content { // https://www.freshbooks.com/api/me_endpoint
    let id: Int
    let name: String
    let accountID: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case accountID = "account_id"
    }
}
