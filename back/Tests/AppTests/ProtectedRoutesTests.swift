//
//  ProtectedRoutesTests.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

@testable import App
import XCTVapor

final class ProtectedRoutesTests: XCTestCase {
    func testEveryProtectedRouteRefusesARequestWithoutToken() async throws {
        try await withApp { app in
            let id = UUID()
            let routes: [(HTTPMethod, String)] = [
                (.GET, "games"),
                (.POST, "games"),
                (.GET, "games/\(id)"),
                (.PUT, "games/\(id)"),
                (.DELETE, "games/\(id)"),
                (.GET, "members"),
                (.POST, "members"),
                (.GET, "members/\(id)"),
                (.PUT, "members/\(id)"),
                (.DELETE, "members/\(id)"),
                (.GET, "members/\(id)/loans"),
                (.POST, "loans"),
                (.GET, "loans/overdue"),
                (.POST, "loans/\(id)/return"),
            ]

            for (method, path) in routes {
                try await app.test(method, path, afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized, "\(method) /\(path) devrait exiger un jeton")
                })
            }
        }
    }

    func testProtectedRouteRefusesAMalformedToken() async throws {
        try await withApp { app in
            try await app.test(.GET, "games", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: "not-a-jwt")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testProtectedRouteAcceptsAValidToken() async throws {
        try await withApp { app in
            try await app.testAuthorized(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }
}
