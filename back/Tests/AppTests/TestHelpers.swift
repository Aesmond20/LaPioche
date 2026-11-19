@testable import App
import XCTVapor

private struct StaffTokenKey: StorageKey {
    typealias Value = String
}

func withApp(_ test: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        app.storage[StaffTokenKey.self] = try await registerUser(app, email: "tests@example.com").token
        try await test(app)
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

extension Application {
    @discardableResult
    func testAuthorized(
        _ method: HTTPMethod,
        _ path: String,
        beforeRequest: (inout XCTHTTPRequest) async throws -> Void = { _ in },
        afterResponse: (XCTHTTPResponse) async throws -> Void = { _ in }
    ) async throws -> XCTApplicationTester {
        let token = try XCTUnwrap(storage[StaffTokenKey.self])
        return try await test(method, path, beforeRequest: { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            try await beforeRequest(&req)
        }, afterResponse: afterResponse)
    }
}

func createGame(
    _ app: Application,
    title: String = "Catan",
    minPlayers: Int = 3,
    maxPlayers: Int = 4,
    durationMinutes: Int = 90
) async throws -> GameDTO {
    var game: GameDTO?
    try await app.testAuthorized(.POST, "games", beforeRequest: { req in
        try req.content.encode(CreateGameDTO(
            title: title,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            durationMinutes: durationMinutes
        ))
    }, afterResponse: { res async throws in
        game = try res.content.decode(GameDTO.self)
    })
    return try XCTUnwrap(game)
}

func createMember(
    _ app: Application,
    name: String = "Camille",
    email: String = "camille@example.com"
) async throws -> MemberDTO {
    var member: MemberDTO?
    try await app.testAuthorized(.POST, "members", beforeRequest: { req in
        try req.content.encode(CreateMemberDTO(name: name, email: email))
    }, afterResponse: { res async throws in
        member = try res.content.decode(MemberDTO.self)
    })
    return try XCTUnwrap(member)
}

func insertLoan(
    _ app: Application,
    gameID: UUID,
    memberID: UUID,
    borrowedAt: Date,
    dueAt: Date,
    returnedAt: Date? = nil
) async throws {
    let loan = Loan(gameID: gameID, memberID: memberID, borrowedAt: borrowedAt, dueAt: dueAt)
    loan.returnedAt = returnedAt
    try await loan.save(on: app.db)
}

func registerUser(
    _ app: Application,
    email: String = "staff@example.com",
    password: String = "correct-horse"
) async throws -> AuthResponseDTO {
    var auth: AuthResponseDTO?
    try await app.test(.POST, "auth/register", beforeRequest: { req in
        try req.content.encode(CredentialsDTO(email: email, password: password))
    }, afterResponse: { res async throws in
        auth = try res.content.decode(AuthResponseDTO.self)
    })
    return try XCTUnwrap(auth)
}
