import FluentSQLite
import Vapor
import Leaf
import Authentication

/// Called before your application initializes.
public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {
    // Register providers first
    try services.register(FluentSQLiteProvider())
    try services.register(LeafProvider())
    config.prefer(LeafRenderer.self, for: ViewRenderer.self)

    /// Create default content config
    var contentConfig = ContentConfig.default()

    /// Create custom JSON encoder
    let jsonDecoder = JSONDecoder()
    let formatter = DateFormatter()
    formatter.dateFormat = "YYYY-MM-DD HH:mm:ss"
    jsonDecoder.dateDecodingStrategy = .formatted(formatter)

    /// Register JSON encoder and content config
    contentConfig.use(decoder: jsonDecoder, for: .json)
    contentConfig.use(decoder: jsonDecoder, for: .jsonAPI)

    services.register(contentConfig)

    // Register routes to the router
    let router = EngineRouter.default()
    try routes(router)
    services.register(router, as: Router.self)
    try services.register(AuthenticationProvider())

    config.prefer(MemoryKeyedCache.self, for: KeyedCache.self)

    // Register middleware
    var middlewares = MiddlewareConfig() // Create _empty_ middleware config
    middlewares.use(SessionsMiddleware.self)
    middlewares.use(ErrorMiddleware.self) // Catches errors and converts to HTTP response
    services.register(middlewares)

    // Configure a SQLite database
    let sqlite = try SQLiteDatabase(storage: .memory)

    // Register the configured SQLite database to the database config.
    var databases = DatabasesConfig()
    databases.add(database: sqlite, as: .sqlite)
    services.register(databases)


    // Configure migrations
    var migrations = MigrationConfig()
    migrations.add(model: User.self, database: .sqlite)
    migrations.add(model: Webhook.self, database: .sqlite)
    migrations.add(model: FreshbooksInvoice.self, database: .sqlite)
    services.register(migrations)
}
