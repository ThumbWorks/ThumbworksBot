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
extension URL {
    static let freshbooksAuth = URL(string: "\(String.freshbooksAPIHost)/auth/oauth/token")!
    static let freshbooksUser = URL(string: "\(String.freshbooksAPIHost)/auth/api/v1/users/me")!

    static func freshbooksInvoicesURL(accountID: String) -> URL {
        return URL(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices")!
    }
    static func freshbooksInvoiceURL(accountID: String, invoiceID: Int) -> URL? {
        return URL(string: "\(String.freshbooksAPIHost)/accounting/account/\(accountID)/invoices/invoices/\(invoiceID)")
    }

    static func freshbooksCallbackURL(accountID: String, objectID: Int) -> URL? {
        return URL(string: "\(String.freshbooksAPIHost)/events/account/\(accountID)/events/callbacks/\(objectID)")
    }

    static func freshbooksCallbacksURL(accountID: String) -> URL? {
        return URL(string: "\(String.freshbooksAPIHost)/events/account/\(accountID)/events/callbacks")
    }
}

/// @mockable
protocol FreshbooksWebServicing {
    func deleteWebhook(accountID: String, on req: Request) throws -> EventLoopFuture<Response>
    func registerNewWebhook(accountID: String, accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus>
    func fetchWebhooks(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult>
    func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksInvoice>
    func fetchUser(accessToken: String, on req: Request) throws -> EventLoopFuture<UserFetchResponsePayload>
    func allInvoices(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<[FreshbooksInvoice]>
    func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus>
    func auth(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse>
}

class FreshbooksHeaderProvider {
    let accessToken: String
    let response: Response?

    init(accessToken: String, bodyContent: Response? = nil) {
        self.accessToken = accessToken
        self.response = bodyContent
    }
    func setHeaders(request: Request) throws -> () {
        if let response = response?.http.body {
            request.http.body = response
        }
        request.http.contentType = .json
        request.http.headers.add(name: .accept, value: "application/json")
        request.http.headers.add(name: "Api-Version", value: "alpha")
        request.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
    }
}

final class FreshbooksWebservice: FreshbooksWebServicing {
    let clientSecret: String
    let clientID: String
    let hostname: String

    init(hostname: String, clientID: String, clientSecret: String) {
        self.hostname = hostname
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    func allInvoices(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<[FreshbooksInvoice]> {

        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        let client = try req.client()
        return client.get(URL.freshbooksInvoicesURL(accountID: accountID), beforeSend: provider.setHeaders).flatMap { response in
            do {
                return try response.content.decode(InvoicesPackage.self).map {  $0.response.result.invoices }
            }
            catch {
                print(error)
                throw InvoiceError.notParsed
            }
        }
    }
    func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksInvoice> {
        guard let url = URL.freshbooksInvoiceURL(accountID: accountID, invoiceID: invoiceID) else {
            throw FreshbooksError.invalidURL
        }
        let client = try req.client()
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)

        return client.get(url, beforeSend: provider.setHeaders).flatMap { response in
            try response.content.decode(InvoicePackage.self).map({ package  in
                return package.response.result.invoice
            })
        }
    }




    func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let client = try req.client()
        return try req.content.decode(FreshbooksWebhookTriggeredContent.self).flatMap { payload in
            guard let url = URL.freshbooksCallbackURL(accountID: payload.accountID, objectID: payload.objectID) else {
                throw FreshbooksError.invalidURL
            }
            guard let verifier = payload.verifier else {
                throw FreshbooksError.noVerifierAttribute
            }
            let callback = FreshbooksCallback(callbackID: payload.objectID, verifier: verifier)
            return try FreshbookConfirmReadyPayload(callback: callback)
                .encode(for: req)
                .flatMap { confirmedReadyPayload -> EventLoopFuture<HTTPStatus> in
                    let provider = FreshbooksHeaderProvider(accessToken: accessToken, bodyContent: confirmedReadyPayload)
                   return client.put(url, beforeSend: provider.setHeaders)
                    .transform(to: HTTPStatus.ok)
            }
        }
    }

    func deleteWebhook(accountID: String, on req: Request) throws -> EventLoopFuture<Response> {
        let client = try req.client()
        guard let accessToken = try req.session()["accessToken"] else {
            throw UserError.noAccessToken
        }
        let deletePayload = try req.query.decode(DeleteWebhookRequestPayload.self)
        guard let url = URL.freshbooksCallbackURL(accountID: accountID, objectID: deletePayload.id) else {
            throw FreshbooksError.invalidURL
        }
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return client.delete(url, beforeSend: provider.setHeaders)
    }

    func registerNewWebhook(accountID: String, accessToken: String, on req: Request) throws -> EventLoopFuture<HTTPStatus> {
          let callback = NewWebhookCallbackRequest(event: "invoice.create", uri: "\(hostname)/webhooks/ready")

          let requestPayload = CreateWebhookRequestPayload(callback: callback)

          guard let url = URL.freshbooksCallbacksURL(accountID: accountID) else {
              throw FreshbooksError.invalidURL
          }

        return try requestPayload.encode(using: req).flatMap { request in
            let body = request.http.body
            let client = try req.client()
            return client.post(url) { webhookRequest in
                webhookRequest.http.body = body
                webhookRequest.http.contentType = .json
                webhookRequest.http.headers.add(name: .authorization, value: "Bearer \(accessToken)")
            }.flatMap({ (response)  in
                // for whatever reason, couldn't parse the content properly, reverting to the old way
                guard let data = response.http.body.data,
                    let json = try? JSONSerialization.jsonObject(with: data, options: []),
                    let dict = json as? [String: Any],
                    let response = dict["response"] as? [String: Any],
                    let result = response["result"] as? [String: Any],
                    let callback = result["callback"] as? [String: Any],
                    let webhookID = callback["callbackid"] as? Int else {
                        throw FreshbooksError.unableToParseWebhookObject
                }
                let user = try req.requireAuthenticated(User.self)
                let newWebhook = Webhook(webhookID: webhookID, userID: try user.requireID())
                return newWebhook.save(on: req).transform(to: .ok)
            })
        }
    }

    func fetchWebhooks(accountID: String, accessToken: String, req: Request) throws -> EventLoopFuture<FreshbooksWebhookResponseResult> {
        guard let url = URL.freshbooksCallbacksURL(accountID: accountID) else {
            throw FreshbooksError.invalidURL
        }
        let provider = FreshbooksHeaderProvider(accessToken: accessToken)
        return try req.client().get(url, beforeSend: provider.setHeaders)
            .flatMap({ response in
            response.http.contentType = .json
            return try response.content.decode(FreshbooksWebhookResponsePayload.self)
                .flatMap({ payload in
                    req.future().map { payload.response.result }
                })
        })
    }

    func auth(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse> {
        return try exchangeToken(with: code, on: req)
    }

    private func exchangeToken(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse>{
        return try TokenExchangeRequest(clientSecret: clientSecret,
                                        redirectURI: URL(string: "\(hostname)/freshbooks/auth"),
                                        clientID: clientID,
                                        code: code)
            .encode(using: req)
            .flatMap { tokenRequest -> EventLoopFuture<TokenExchangeResponse> in
                return try req.client().post(URL.freshbooksAuth) { request in
                    request.http.contentType = .json
                    request.http.body = tokenRequest.http.body
                }.flatMap { tokenExchangeResponse -> EventLoopFuture<TokenExchangeResponse> in
                    return try tokenExchangeResponse.content.decode(TokenExchangeResponse.self)
                }
        }
    }

    func fetchUser(accessToken: String, on req: Request)  throws ->  EventLoopFuture<UserFetchResponsePayload> {
        return try UserFetchRequest(accessToken: accessToken).encode(for: req)
            .flatMap { userFetchResponse -> EventLoopFuture<UserFetchResponsePayload> in
                let provider = FreshbooksHeaderProvider(accessToken: accessToken)
                return try req.client().get(URL.freshbooksUser, beforeSend: provider.setHeaders)
                    .flatMap { userFetchResponse in
                        let userFetchResponseObject = try userFetchResponse.content.decode(UserFetchResponsePayload.self)
                        return userFetchResponseObject
                }
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
    let userID: Int
    let name: String
    let objectID: Int
    let verified: Bool?
    let verifier: String?
    let accountID: String
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
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

private struct DeleteWebhookRequestPayload: Codable {
    let id: Int
}

struct FreshbooksWebhookResponseResult: Codable, Content {
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
            let invoice: FreshbooksInvoice
        }
    }

}
struct InvoicesPackage: Content {
    let response: InvoicesResult

    struct InvoicesResult: Content {
        let result: Invoices
        struct Invoices: Content {
            let invoices: [FreshbooksInvoice]
        }
    }
}

struct FreshbooksInvoice: Content, Equatable {
    let id: Int
    let status: Int
    let paymentStatus: String
    let currentOrganization: String
    let amount: Amount
    let createdAt: Date

    struct Amount: Content, Equatable {
        let amount: String
        let code: String
    }
    enum CodingKeys: String, CodingKey {
        case status, id, amount
        case createdAt = "created_at"
        case paymentStatus = "payment_status"
        case currentOrganization = "current_organization"
    }
}

struct TokenExchangeResponse: Content {
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
