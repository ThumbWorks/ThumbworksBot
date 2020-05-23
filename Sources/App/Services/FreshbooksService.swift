//
//  FreshbooksService.swift
//  App
//
//  Created by Roderic Campbell on 5/8/20.
//

import Vapor

extension String {
    static let freshbooksAPIHost = "https://api.freshbooks.com"
}
extension URI {
    static let freshbooksAuth = URI(string: "\(String.freshbooksAPIHost)/auth/oauth/token")

    static let freshbooksUser = URI(string: "\(String.freshbooksAPIHost)/auth/api/v1/users/me")

    static func freshbooksInvoicesURL(accountID: String, page: Int?) -> URI {
        if let page = page {
            return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices?page=\(page)")
        }
        return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices")
    }
    static func freshbooksInvoiceURL(accountID: String, invoiceID: Int) -> URI {
        return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices/\(invoiceID)")
    }

    static func freshbooksCallbackURL(accountID: String, objectID: Int) -> URI {
        return URI(string: "\(String.freshbooksAPIHost)/events/account/\(accountID)/events/callbacks/\(objectID)")
    }

    static func freshbooksCallbacksURL(accountID: String) -> URI {
        return URI(string: "\(String.freshbooksAPIHost)/events/account/\(accountID)/events/callbacks")
    }
}

/// @mockable
public protocol FreshbooksWebServicing {
    func deleteWebhook(accountID: String, webhookID: Int, on req: Request) throws -> EventLoopFuture<ClientResponse>
    func registerNewWebhook(accountID: String, accessToken: String, on req: Request) throws -> EventLoopFuture<NewWebhookPayload>
    func fetchWebhooks(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult>
    func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksInvoiceContent>
    func fetchUser(accessToken: String, on req: Request) throws -> EventLoopFuture<UserFetchResponsePayload>
    func fetchInvoices(accountID: String, accessToken: String, page: Int, on req: Request) throws -> EventLoopFuture<InvoicesMetaDataContent>
    func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<ClientResponse>
    func auth(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse>
}

class FreshbooksHeaderProvider {
    let accessToken: String
    let response: Response?

    func headers() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: .accept, value: "application/json")
        headers.add(name: "Api-Version", value: "alpha")
        headers.add(name: .authorization, value: "Bearer \(accessToken)")
        return headers
    }
    init(accessToken: String, bodyContent: Response? = nil) {
        self.accessToken = accessToken
        self.response = bodyContent
    }
//    func setHeaders(request: Request) throws -> () {
//        if let response = response?.http.body {
//            request.http.body = response
//        }
//        request.http.contentType = .json
//        request.http.headers.add(name: .accept, value: "application/json")
//        request.http.headers.add(name: "Api-Version", value: "alpha")
//        request.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
//    }
}

public final class FreshbooksWebservice: FreshbooksWebServicing {

    let clientSecret: String
    let clientID: String
    let hostname: String

    public init(hostname: String, clientID: String, clientSecret: String) {
        self.hostname = hostname
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    // An attempt was made to add this call with a job
    public func fetchInvoices(accountID: String, accessToken: String, page: Int, on req: Request) throws -> EventLoopFuture<InvoicesMetaDataContent> {

        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        let client = req.client
        let url = URI.freshbooksInvoicesURL(accountID: accountID, page: page)
        print(url)
        return client.get(url, headers: provider.headers())
            .flatMapThrowing { clientResponse in
                let result = try clientResponse.content.decode(InvoicesPackage.self).response.result
                result.invoices.forEach {print($0.createdAt)}
                return try clientResponse.content.decode(InvoicesPackage.self).response.result
        }
    }

    public func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksInvoiceContent> {
        let url = URI.freshbooksInvoiceURL(accountID: accountID, invoiceID: invoiceID)
        let client = req.client
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)

        return client.get(url, headers: provider.headers()).flatMapThrowing { response in
            let package = try response.content.decode(InvoicePackage.self)
            return package.response.result.invoice
        }
    }

    public func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<ClientResponse> {
        let client = req.client
        let payload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        let url = URI.freshbooksCallbackURL(accountID: payload.accountID, objectID: payload.objectID)
        guard let verifier = payload.verifier else {
            throw FreshbooksError.noVerifierAttribute
        }
        let callback = FreshbooksCallback(callbackID: payload.objectID, verifier: verifier)
        let confirmedReadyPayload = FreshbookConfirmReadyPayload(callback: callback)
            .encodeResponse(for: req)

        return confirmedReadyPayload.flatMap { confirmedReadyPayload  in
            let provider = FreshbooksHeaderProvider(accessToken: accessToken, bodyContent: confirmedReadyPayload)
            return client.put(url, headers: provider.headers())
        }
    }

    public func deleteWebhook(accountID: String, webhookID: Int, on req: Request) throws -> EventLoopFuture<ClientResponse> {
        let client = req.client
        guard let accessToken = req.session.data["accessToken"] else {
            throw UserError.noAccessToken
        }
        let url = URI.freshbooksCallbackURL(accountID: accountID, objectID: webhookID)
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return client.delete(url, headers: provider.headers())
    }

    public func registerNewWebhook(accountID: String, accessToken: String, on req: Request) throws -> EventLoopFuture<NewWebhookPayload> {
        let callback = NewWebhookCallbackRequest(event: "invoice.create", uri: "\(hostname)/webhooks/ready")
        let requestPayload = CreateWebhookRequestPayload(callback: callback)
        let url = URI.freshbooksCallbacksURL(accountID: accountID)
        let client = req.client
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return client.post(url, headers: provider.headers()) { webhookRequest in
            try webhookRequest.content.encode(requestPayload)
        }.flatMapThrowing {  response -> NewWebhookPayload in
            // TODO we could afford some better error handling here. Attemping to register a webhook after it's already been created gives a 422 and a different payload in the response
            let decoded = try response.content.decode(NewWebhookPayload.self)
            return decoded
        }
    }

    public func fetchWebhooks(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult> {
        let url = URI.freshbooksCallbacksURL(accountID: accountID)
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)

        return req.client.get(url, headers: provider.headers())
            .flatMapThrowing { response in
                try response.content.decode(FreshbooksWebhookResponsePayload.self).response.result
        }
    }

    public func auth(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse> {
        return try exchangeToken(with: code, on: req)
    }

    private func exchangeToken(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse>{
        let requestPayload = TokenExchangeRequest(clientSecret: clientSecret,
                                                  redirectURI: URL(string: "\(hostname)/freshbooks/auth"),
                                                  clientID: clientID,
                                                  code: code)
        return req.client.post(URI.freshbooksAuth) { request in
            request.headers.add(name: .contentType, value: "application/json")
            try request.content.encode(requestPayload)
        }.flatMapThrowing { clientResponse in
            return try clientResponse.content.decode(TokenExchangeResponse.self)
        }
    }

    public func fetchUser(accessToken: String, on req: Request)  throws ->  EventLoopFuture<UserFetchResponsePayload> {
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)

        let userEndpoint = URI.freshbooksUser
        return req.client.get(userEndpoint, headers: provider.headers())
        .flatMapThrowing { clientResponse in
            return try clientResponse.content.decode(UserFetchResponsePayload.self)
        }
    }
}

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

private struct FreshbooksWebhookResponsePayload: Codable, Content {
    let response: FreshbooksWebhookResponseResponse

}
private struct FreshbooksWebhookResponseResponse: Codable, Content {
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

struct FreshbooksWebhookCallbackResponse: Codable, Content {
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
