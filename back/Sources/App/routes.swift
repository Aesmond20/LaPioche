import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: AuthController())
    
    let protected = app.grouped(UserTokenMiddleware())
    try protected.register(collection: GameController())
    try protected.register(collection: MemberController())
    try protected.register(collection: LoanController())
}
