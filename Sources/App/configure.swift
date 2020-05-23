import Vapor
import Leaf
import FluentSQLiteDriver
import FluentSQL
import Fluent
//import Jobs

/// Called before your application initializes.
public func configure(_ app: Application) throws {

//public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {
    // Register providers first
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    }
    app.migrations.add(CreateUser())
    app.migrations.add(CreateMembership())
    app.migrations.add(CreateBusiness())
    app.migrations.add(CreateMembershipBusiness())
    app.migrations.add(CreateWebhook())
    app.migrations.add(CreateInvoice())
    app.sessions.use(.fluent(.sqlite))
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
    app.middleware.use(app.sessions.middleware)


    try routes(app)  

}
