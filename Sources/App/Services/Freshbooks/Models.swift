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
enum FreshbooksError: Error {
    case invalidURL
    case noAccessTokenFound
    case noVerifierAttribute
    case unableToParseWebhookObject
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
