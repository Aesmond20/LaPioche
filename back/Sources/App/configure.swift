import Fluent
import FluentSQLiteDriver
import JWT
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.port = 8081

    let cors = CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .contentType, .origin, .authorization]
    ))
    // CORS must wrap the error middleware so that error responses carry its headers too.
    app.middleware = .init()
    app.middleware.use(cors)
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))

    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    let developmentJWTSecret = "development-only-jwt-secret-do-not-use-in-production"
       guard let jwtSecret = Environment.get("JWT_SECRET") ?? (app.environment == .production ? nil : developmentJWTSecret) else {
           throw Abort(.internalServerError, reason: "JWT_SECRET must be set in production")
       }
       await app.jwt.keys.add(hmac: HMACKey(from: jwtSecret), digestAlgorithm: .sha256)
    
    app.migrations.add(CreateGame())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateLoan())
    app.migrations.add(CreateUser())
    try await app.autoMigrate()

    try routes(app)
}
