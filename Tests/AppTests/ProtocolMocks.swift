///
/// @Generated by Mockolo
///



import Vapor
@testable import App


public class SlackWebServicingMock: SlackWebServicing {
    public init() { }


    public var sendSlackPayloadCallCount = 0
    public var sendSlackPayloadHandler: ((String, Emoji?, Request) throws -> (EventLoopFuture<ClientResponse>))?
    public func sendSlackPayload(text: String, with emoji: Emoji?, on req: Request) throws -> EventLoopFuture<ClientResponse> {
        sendSlackPayloadCallCount += 1
        if let sendSlackPayloadHandler = sendSlackPayloadHandler {
            return try sendSlackPayloadHandler(text, emoji, req)
        }
        fatalError("sendSlackPayloadHandler returns can't have a default value thus its handler must be set")
    }
}

public class FreshbooksWebServicingMock: FreshbooksWebServicing {
    public init() { }


    public var deleteWebhookCallCount = 0
    public var deleteWebhookHandler: ((String, Int, Request) throws -> (EventLoopFuture<Void>))?
    public func deleteWebhook(accountID: String, webhookID: Int, on req: Request) throws -> EventLoopFuture<Void> {
        deleteWebhookCallCount += 1
        if let deleteWebhookHandler = deleteWebhookHandler {
            return try deleteWebhookHandler(accountID, webhookID, req)
        }
        fatalError("deleteWebhookHandler returns can't have a default value thus its handler must be set")
    }

    public var registerNewWebhookCallCount = 0
    public var registerNewWebhookHandler: ((String, String, WebhookType, Client) throws -> (EventLoopFuture<NewWebhookPayloadCallback>))?
    public func registerNewWebhook(accountID: String, accessToken: String, type: WebhookType, with client: Client) throws -> EventLoopFuture<NewWebhookPayloadCallback> {
        registerNewWebhookCallCount += 1
        if let registerNewWebhookHandler = registerNewWebhookHandler {
            return try registerNewWebhookHandler(accountID, accessToken, type, client)
        }
        fatalError("registerNewWebhookHandler returns can't have a default value thus its handler must be set")
    }

    public var fetchWebhooksCallCount = 0
    public var fetchWebhooksHandler: ((String, String, Int, Request) throws -> (EventLoopFuture<WebhookResponseResult>))?
    public func fetchWebhooks(accountID: String, accessToken: String, page: Int, req: Request) throws -> EventLoopFuture<WebhookResponseResult> {
        fetchWebhooksCallCount += 1
        if let fetchWebhooksHandler = fetchWebhooksHandler {
            return try fetchWebhooksHandler(accountID, accessToken, page, req)
        }
        fatalError("fetchWebhooksHandler returns can't have a default value thus its handler must be set")
    }

    public var fetchInvoiceCallCount = 0
    public var fetchInvoiceHandler: ((String, Int, String, Request) throws -> (EventLoopFuture<InvoiceContent>))?
    public func fetchInvoice(accountID: String, invoiceID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<InvoiceContent> {
        fetchInvoiceCallCount += 1
        if let fetchInvoiceHandler = fetchInvoiceHandler {
            return try fetchInvoiceHandler(accountID, invoiceID, accessToken, req)
        }
        fatalError("fetchInvoiceHandler returns can't have a default value thus its handler must be set")
    }

    public var fetchClientCallCount = 0
    public var fetchClientHandler: ((String, Int, String, Request) throws -> (EventLoopFuture<ClientContent>))?
    public func fetchClient(accountID: String, clientID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<ClientContent> {
        fetchClientCallCount += 1
        if let fetchClientHandler = fetchClientHandler {
            return try fetchClientHandler(accountID, clientID, accessToken, req)
        }
        fatalError("fetchClientHandler returns can't have a default value thus its handler must be set")
    }

    public var fetchPaymentCallCount = 0
    public var fetchPaymentHandler: ((String, Int, String, Request) throws -> (EventLoopFuture<PaymentContent>))?
    public func fetchPayment(accountID: String, paymentID: Int, accessToken: String, req: Request) throws -> EventLoopFuture<PaymentContent> {
        fetchPaymentCallCount += 1
        if let fetchPaymentHandler = fetchPaymentHandler {
            return try fetchPaymentHandler(accountID, paymentID, accessToken, req)
        }
        fatalError("fetchPaymentHandler returns can't have a default value thus its handler must be set")
    }

    public var fetchUserCallCount = 0
    public var fetchUserHandler: ((String, Request) throws -> (EventLoopFuture<UserResponseObject>))?
    public func fetchUser(accessToken: String, on req: Request) throws -> EventLoopFuture<UserResponseObject> {
        fetchUserCallCount += 1
        if let fetchUserHandler = fetchUserHandler {
            return try fetchUserHandler(accessToken, req)
        }
        fatalError("fetchUserHandler returns can't have a default value thus its handler must be set")
    }

    public var fetchInvoicesCallCount = 0
    public var fetchInvoicesHandler: ((String, String, Int, Client) throws -> (EventLoopFuture<InvoicesMetaDataContent>))?
    public func fetchInvoices(accountID: String, accessToken: String, page: Int, with client: Client) throws -> EventLoopFuture<InvoicesMetaDataContent> {
        fetchInvoicesCallCount += 1
        if let fetchInvoicesHandler = fetchInvoicesHandler {
            return try fetchInvoicesHandler(accountID, accessToken, page, client)
        }
        fatalError("fetchInvoicesHandler returns can't have a default value thus its handler must be set")
    }

    public var confirmWebhookCallCount = 0
    public var confirmWebhookHandler: ((String, Request) throws -> (EventLoopFuture<Void>))?
    public func confirmWebhook(accessToken: String, on req: Request) throws -> EventLoopFuture<Void> {
        confirmWebhookCallCount += 1
        if let confirmWebhookHandler = confirmWebhookHandler {
            return try confirmWebhookHandler(accessToken, req)
        }
        fatalError("confirmWebhookHandler returns can't have a default value thus its handler must be set")
    }

    public var authCallCount = 0
    public var authHandler: ((String, Request) throws -> (EventLoopFuture<TokenExchangeResponse>))?
    public func auth(with code: String, on req: Request) throws -> EventLoopFuture<TokenExchangeResponse> {
        authCallCount += 1
        if let authHandler = authHandler {
            return try authHandler(code, req)
        }
        fatalError("authHandler returns can't have a default value thus its handler must be set")
    }
}

