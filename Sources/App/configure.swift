import Vapor
import Leaf
import FluentPostgresDriver
import Fluent
import QueuesFluentDriver

/// Called before your application initializes.
public func configure(_ app: Application, dependencies: ApplicationDependencies) throws {
    // Register providers first
    if app.environment == .development {
        app.databases.use(.postgres(hostname: "localhost", username: "roderic", password: "vapor", database: "vapordev1"), as: .psql)
    } else if app.environment == .testing {
        app.databases.use(.postgres(hostname: "localhost", username: "roderic", password: "vapor", database: "vaportest"), as: .psql)
    } else {
        guard let host = dependencies.databaseURLString else {
            throw RouterError.missingDatabaseHostURL
        }
        app.databases.use(try .postgres(url: host), as: .psql)
    }
    app.migrations.add(CreateBusiness())
    app.migrations.add(CreateUser())
    app.migrations.add(CreateMembership())
    app.migrations.add(CreateMembershipBusiness())
    app.migrations.add(CreateWebhook())
    app.migrations.add(CreateInvoice())
    app.migrations.add(JobModelMigrate())
    app.sessions.use(.fluent(.psql))

    app.migrations.add(SessionRecord.migration)
    
    try app.autoMigrate().wait()
    app.views.use(.leaf)

    /// Create default content config
    let encoder = JSONEncoder()
    let formatter = DateFormatter()
    formatter.dateFormat = "YYYY-MM-DD HH:mm:ss"
    encoder.dateEncodingStrategy = .formatted(formatter)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(formatter)

    // override the global encoder used for the `.json` media type
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .jsonAPI)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    app.queues.use(.fluent())
    app.queues.add(RegisterWebhookJob())
    app.queues.add(GetInvoiceJob())
    try routes(app, dependencies: dependencies)

    try app.queues.startInProcessJobs(on: .default)

}
