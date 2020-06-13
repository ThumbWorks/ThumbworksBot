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

    static func invoices(accountID: String, page: Int?) -> URI {
        if let page = page {
            return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices?page=\(page)")
        }
        return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices")
    }

    static func invoice(accountID: String, invoiceID: Int) -> URI {
        return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices/\(invoiceID)")
    }

    static func payment(accountID: String, paymentID: Int) -> URI {
        return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/payments/payments/\(paymentID)")
    }

    static func client(accountID: String, clientID: Int) -> URI {
        return URI(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/users/clients/\(clientID)")
    }

    static func eventCallback(accountID: String, objectID: Int) -> URI {
        return URI(string: "\(String.freshbooksAPIHost)/events/account/\(accountID)/events/callbacks/\(objectID)")
    }

    static func eventCallbacks(accountID: String, page: Int?) -> URI {
        if let page = page {
            return URI(string: "\(String.freshbooksAPIHost)/events/account/\(accountID)/events/callbacks?page=\(page)")
        }
        return URI(string: "\(String.freshbooksAPIHost)/events/account/\(accountID)/events/callbacks")
    }
}

/// @mockable
public protocol FreshbooksWebServicing {
    func deleteWebhook(accountID: String, webhookID: Int, on req: Request) -> EventLoopFuture<Void>
    func registerNewWebhook(accountID: String, accessToken: String, type: WebhookType, with client: Client) -> EventLoopFuture<NewWebhookPayloadCallback>
    func fetchWebhooks(accountID: String, accessToken: String, page: Int, req: Request) -> EventLoopFuture<WebhookResponseResult>
    func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) -> EventLoopFuture<InvoiceContent>
    func fetchClient(accountID: String, clientID: Int, accessToken: String, req: Request) -> EventLoopFuture<ClientContent>
    func fetchPayment(accountID: String, paymentID: Int, accessToken: String, req: Request) -> EventLoopFuture<PaymentContent>
    func fetchUser(accessToken: String, on req: Request) -> EventLoopFuture<UserResponseObject>
    func fetchInvoices(accountID: String, accessToken: String, page: Int, with client: Client) -> EventLoopFuture<InvoicesMetaDataContent>
    func confirmWebhook(accessToken: String, accountID: String, objectID: Int, verifier: String, on req: Request) -> EventLoopFuture<Void>
    func auth(with code: String, on req: Request) -> EventLoopFuture<TokenExchangeResponse>
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
}

// MARK: - FreshbooksWebServicing public facing
public final class FreshbooksWebservice: FreshbooksWebServicing {

    let clientSecret: String
    let clientID: String
    let hostname: String

    public init(hostname: String, clientID: String, clientSecret: String) {
        self.hostname = hostname
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public func fetchClient(accountID: String, clientID: Int, accessToken: String, req: Request) -> EventLoopFuture<ClientContent> {
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        let url = URI.client(accountID: accountID, clientID: clientID)
        return genericRequest(method: .GET, url: url, headers: provider.headers(), returnType: ClientPayload.self, with: req.client)
            .map { $0.response.result.client }
    }

    public func fetchPayment(accountID: String, paymentID: Int, accessToken: String, req: Request) -> EventLoopFuture<PaymentContent> {
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        let url = URI.payment(accountID: accountID, paymentID: paymentID)
        return genericRequest(method: .GET, url: url, headers: provider.headers(), returnType: PaymentPayload.self, with: req.client)
            .map { $0.response.result.payment }
    }

    // An attempt was made to add this call with a job
    public func fetchInvoices(accountID: String, accessToken: String, page: Int, with client: Client) -> EventLoopFuture<InvoicesMetaDataContent> {
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        let url = URI.invoices(accountID: accountID, page: page)
        return genericRequest(method: .GET, url: url, headers: provider.headers(), returnType: InvoicesPackage.self, with: client)
            .map { $0.response.result }
    }

    public func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) -> EventLoopFuture<InvoiceContent> {
        let url = URI.invoice(accountID: accountID, invoiceID: invoiceID)
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return genericRequest(method: .GET, url: url, headers: provider.headers(), returnType: InvoicePackage.self, with: req.client)
            .map { $0.response.result.invoice }
    }

    public func confirmWebhook(accessToken: String, accountID: String, objectID: Int, verifier: String, on req: Request) -> EventLoopFuture<Void> {
        let client = req.client
//        let payload = try req.content.decode(FreshbooksWebhookTriggeredContent.self)
        let url = URI.eventCallback(accountID: accountID, objectID: objectID)
//        guard let verifier = verifier else {
//            return req.eventLoop.makeFailedFuture(FreshbooksError.noVerifierAttribute)
//        }
        let callback = FreshbooksCallback(callbackID: objectID, verifier: verifier)
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        
        return client.put(url, headers: provider.headers(), beforeSend: { request in
            try request.content.encode(FreshbookConfirmReadyPayload(callback: callback))
        })
        .map { _ in Void() }
    }

    public func deleteWebhook(accountID: String, webhookID: Int, on req: Request) -> EventLoopFuture<Void> {
        let client = req.client
        guard let accessToken = req.session.data["accessToken"] else {
            return req.eventLoop.makeFailedFuture(UserError.noAccessToken)
        }
        let url = URI.eventCallback(accountID: accountID, objectID: webhookID)
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return client.delete(url, headers: provider.headers()).map { _ in Void() }
    }

    public func registerNewWebhook(accountID: String, accessToken: String, type: WebhookType, with client: Client) -> EventLoopFuture<NewWebhookPayloadCallback> {
        let callback = NewWebhookCallbackRequest(event: type, uri: "\(hostname)/webhooks/ready")
        let requestPayload = CreateWebhookRequestPayload(callback: callback)
        let url = URI.eventCallbacks(accountID: accountID, page: nil)
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return client.post(url, headers: provider.headers()) { webhookRequest in
            try webhookRequest.content.encode(requestPayload)
        }.flatMapThrowing {  response -> NewWebhookPayloadCallback in
            try response.content.decode(NewWebhookPayload.self).response.result.callback
        }
    }

    public func fetchWebhooks(accountID: String, accessToken: String, page: Int, req: Request) -> EventLoopFuture<WebhookResponseResult> {
        let url = URI.eventCallbacks(accountID: accountID, page: page)
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return genericRequest(method: .GET, url: url, headers: provider.headers(), returnType: WebhookResponsePayload.self, with: req.client)
            .map { $0.response.result }
    }

    public func auth(with code: String, on req: Request) -> EventLoopFuture<TokenExchangeResponse> {
        return exchangeToken(with: code, on: req)
    }

    public func fetchUser(accessToken: String, on req: Request) ->  EventLoopFuture<UserResponseObject> {
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        let url = URI.freshbooksUser
        return genericRequest(method: .GET, url: url, headers: provider.headers(), returnType: UserFetchResponsePayload.self, with: req.client)
            .map { $0.response }
    }
}


// MARK: Private helper funcs
private extension FreshbooksWebservice {
    private func exchangeToken(with code: String, on req: Request) -> EventLoopFuture<TokenExchangeResponse>{
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

    /**
     Generic Request which should return an EventLoopFuture<T> where T is the top level json object returned from the response. Consumers of this API should map to the desired content
     - Parameter method: HTTPMethod such as GET, PUT, POST, DELETE
     - Parameter url: The URL for the resource we are attempting to query
     - Parameter headers: the HTTPHeaders to be applied to this request
     - Parameter returnType: The content type of which we are expecting a return
     - Parameter req: The Vapor Request object on which we will perform this request
     */
    private func genericRequest<T: Content>(method: HTTPMethod, url: URI, headers:  HTTPHeaders, returnType: T.Type, with client: Client) -> EventLoopFuture<T> {
        return client.send(method, headers: headers, to: url)
            .flatMapThrowing { clientResponse  in
                do {
                    return try clientResponse.content.decode(returnType.self)
                } catch {
                    // Just catching any errors here. These are documented at https://www.freshbooks.com/api/errors
                    // I noticed this when testing to fetch a random object_id that didn't exist we got a 1012 UnknownResource error
                    let errorPayload = try clientResponse.content.decode(ErrorResponse.self)
                    print(errorPayload.response.errors)
                    if errorPayload.response.errors.first?.errno == 1012 {
                        throw FreshbooksError.invoiceNotFound
                    }
                    throw error
                }
        }
    }
}
