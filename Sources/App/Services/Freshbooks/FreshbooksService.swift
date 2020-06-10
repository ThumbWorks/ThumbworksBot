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
    func registerNewWebhook(accountID: String, accessToken: String, type: WebhookType, with client: Client) throws -> EventLoopFuture<NewWebhookPayload>
    func fetchWebhooks(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult>
    func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksInvoiceContent>
    func fetchUser(accessToken: String, on req: Request) throws -> EventLoopFuture<UserFetchResponsePayload>
    func fetchInvoices(accountID: String, accessToken: String, page: Int, on req: Request) throws -> EventLoopFuture<InvoicesMetaDataContent>
    func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<ClientResponse>
    func auth(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse>
}

class FreshbooksHeaderProvider {
    let accessToken: String
    func headers() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: .accept, value: "application/json")
        headers.add(name: "Api-Version", value: "alpha")
        headers.add(name: .authorization, value: "Bearer \(accessToken)")
        return headers
    }
    init(accessToken: String) {
        self.accessToken = accessToken
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
    public func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksInvoiceContent> {
        let url = URI.freshbooksInvoiceURL(accountID: accountID, invoiceID: invoiceID)
        let client = req.client
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)

        return client.get(url, headers: provider.headers()).flatMapThrowing { response in
            do {
                let package = try response.content.decode(InvoicePackage.self)
                return package.response.result.invoice
            } catch {
                // Just catching any errors here. These are documented at https://www.freshbooks.com/api/errors
                // I noticed this when testing to fetch a random object_id that didn't exist we got a 1012 UnknownResource error
                let errorPayload = try response.content.decode(ErrorResponse.self)
                print(errorPayload.response.errors)
                throw error
            }
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
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return client.put(url, headers: provider.headers(), beforeSend: { request in
            try request.content.encode(FreshbookConfirmReadyPayload(callback: callback))
        })
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

    public func registerNewWebhook(accountID: String, accessToken: String, type: WebhookType, with client: Client) throws -> EventLoopFuture<NewWebhookPayload> {
        let callback = NewWebhookCallbackRequest(event: type, uri: "\(hostname)/webhooks/ready")
        let requestPayload = CreateWebhookRequestPayload(callback: callback)
        let url = URI.freshbooksCallbacksURL(accountID: accountID)
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
