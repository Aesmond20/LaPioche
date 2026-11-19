//
//  AuthTests.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

@testable import App
import JWT
import XCTVapor

final class AuthTests: XCTestCase {
    private struct ErrorBody: Decodable {
        let reason: String
    }

    private func send(
        _ app: Application,
        to path: String,
        email: String,
        password: String,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.POST, path, beforeRequest: { req in
            try req.content.encode(CredentialsDTO(email: email, password: password))
        }, afterResponse: afterResponse)
    }

    private func getMe(
        _ app: Application,
        token: String?,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.GET, "auth/me", beforeRequest: { req in
            if let token {
                req.headers.bearerAuthorization = BearerAuthorization(token: token)
            }
        }, afterResponse: afterResponse)
    }

    // --- Inscription

    func testRegisterReturnsCreatedWithTokenAndUser() async throws {
        try await withApp { app in
            try await send(app, to: "auth/register", email: "staff@example.com", password: "correct-horse") { res in
                XCTAssertEqual(res.status, .created)
                let auth = try res.content.decode(AuthResponseDTO.self)
                XCTAssertFalse(auth.token.isEmpty)
                XCTAssertEqual(auth.user.email, "staff@example.com")
                XCTAssertEqual(auth.expiresAt.timeIntervalSinceNow, 24 * 60 * 60, accuracy: 60)
                XCTAssertFalse(res.body.string.contains("correct-horse"))
                XCTAssertFalse(res.body.string.lowercased().contains("password"))
            }
        }
    }

    func testRegisterStoresOnlyAHashOfThePassword() async throws {
        try await withApp { app in
            _ = try await registerUser(app, password: "correct-horse")

            let storedUser = try await User.query(on: app.db).first()
            let user = try XCTUnwrap(storedUser)
            XCTAssertNotEqual(user.passwordHash, "correct-horse")
            XCTAssertTrue(try Bcrypt.verify("correct-horse", created: user.passwordHash))
        }
    }

    func testRegisterWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await send(app, to: "auth/register", email: "not-an-email", password: "correct-horse") { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testRegisterWithTooShortPasswordIsRejected() async throws {
        try await withApp { app in
            try await send(app, to: "auth/register", email: "staff@example.com", password: "short") { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testRegisterWithEmailAlreadyTakenIgnoringCaseReturnsConflict() async throws {
        try await withApp { app in
            _ = try await registerUser(app, email: "staff@example.com")

            try await send(app, to: "auth/register", email: "STAFF@Example.com", password: "correct-horse") { res in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    // --- Connexion

    func testLoginReturnsTokenAndUser() async throws {
        try await withApp { app in
            _ = try await registerUser(app, email: "staff@example.com", password: "correct-horse")

            try await send(app, to: "auth/login", email: "Staff@Example.com", password: "correct-horse") { res in
                XCTAssertEqual(res.status, .ok)
                let auth = try res.content.decode(AuthResponseDTO.self)
                XCTAssertFalse(auth.token.isEmpty)
                XCTAssertEqual(auth.user.email, "staff@example.com")
            }
        }
    }

    func testLoginWithWrongPasswordReturnsUnauthorized() async throws {
        try await withApp { app in
            _ = try await registerUser(app, password: "correct-horse")

            try await send(app, to: "auth/login", email: "staff@example.com", password: "wrong-password") { res in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
    }

    func testLoginWithUnknownEmailGivesTheSameAnswerAsAWrongPassword() async throws {
        try await withApp { app in
            _ = try await registerUser(app, email: "staff@example.com", password: "correct-horse")
            var wrongPasswordReason: String?
            var unknownEmailReason: String?

            try await send(app, to: "auth/login", email: "staff@example.com", password: "wrong-password") { res in
                wrongPasswordReason = try res.content.decode(ErrorBody.self).reason
            }
            try await send(app, to: "auth/login", email: "nobody@example.com", password: "correct-horse") { res in
                XCTAssertEqual(res.status, .unauthorized)
                unknownEmailReason = try res.content.decode(ErrorBody.self).reason
            }
            XCTAssertNotNil(unknownEmailReason)
            XCTAssertEqual(unknownEmailReason, wrongPasswordReason)
        }
    }

    // --- Compte connecté et refus du jeton

    func testMeReturnsTheConnectedUser() async throws {
        try await withApp { app in
            let auth = try await registerUser(app)

            try await getMe(app, token: auth.token) { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(UserDTO.self).email, "staff@example.com")
            }
        }
    }

    func testMeWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await getMe(app, token: nil) { res in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
    }

    func testMeWithMalformedTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await getMe(app, token: "not-a-jwt") { res in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
    }

    func testMeWithTokenSignedWithAnotherSecretReturnsUnauthorized() async throws {
        try await withApp { app in
            let auth = try await registerUser(app)
            let otherKeys = JWTKeyCollection()
            await otherKeys.add(hmac: HMACKey(from: "another-secret-that-is-long-enough-for-hmac"), digestAlgorithm: .sha256)
            let forgedToken = try await otherKeys.sign(UserPayload(
                subject: SubjectClaim(value: try XCTUnwrap(auth.user.id).uuidString),
                expiration: ExpirationClaim(value: Date().addingTimeInterval(3600))
            ))

            try await getMe(app, token: forgedToken) { res in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
    }

    func testMeWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let auth = try await registerUser(app)
            let expiredToken = try await app.jwt.keys.sign(UserPayload(
                subject: SubjectClaim(value: try XCTUnwrap(auth.user.id).uuidString),
                expiration: ExpirationClaim(value: Date().addingTimeInterval(-60))
            ))

            try await getMe(app, token: expiredToken) { res in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
    }

    func testMeWithTokenOfDeletedAccountReturnsUnauthorized() async throws {
        try await withApp { app in
            let auth = try await registerUser(app)
            try await User.query(on: app.db).delete()

            try await getMe(app, token: auth.token) { res in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
    }
}
