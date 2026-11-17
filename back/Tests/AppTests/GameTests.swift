@testable import App
import XCTVapor

final class GameTests: XCTestCase {
    private func updateGame(
        _ app: Application,
        id: String,
        with dto: CreateGameDTO,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
            try req.content.encode(dto)
        }, afterResponse: afterResponse)
    }
    
    func testCreateGameReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                let game = try res.content.decode(GameDTO.self)
                XCTAssertEqual(game.title, "Catan")
                XCTAssertTrue(game.isAvailable)
            })
        }
    }

    func testCreateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 2)
            })
        }
    }

    func testShowGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(GameDTO.self).id, id)
            })
        }
    }

    func testShowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testShowGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testPreflightRequestFromAnotherOriginIsAllowed() async throws {
        try await withApp { app in
            try await app.test(.OPTIONS, "games", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                req.headers.replaceOrAdd(name: .accessControlRequestMethod, value: "POST")
                req.headers.replaceOrAdd(name: .accessControlRequestHeaders, value: "content-type")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
                XCTAssertTrue(res.headers[.accessControlAllowMethods].joined(separator: ",").contains("POST"))
            })
        }
    }

    func testErrorResponsesCarryTheCorsHeaders() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
            })
        }
    }
    
    func testUpdateGameReturnsUpdatedGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await updateGame(app, id: "\(id)", with: CreateGameDTO(
                title: "Catan Junior", minPlayers: 2, maxPlayers: 4, durationMinutes: 30
            )) { res in
                XCTAssertEqual(res.status, .ok)
                let updated = try res.content.decode(GameDTO.self)
                XCTAssertEqual(updated.id, id)
                XCTAssertEqual(updated.title, "Catan Junior")
                XCTAssertEqual(updated.minPlayers, 2)
                XCTAssertEqual(updated.maxPlayers, 4)
                XCTAssertEqual(updated.durationMinutes, 30)
            }

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(GameDTO.self).title, "Catan Junior")
            })
        }
    }

    func testUpdateBorrowedGameStaysUnavailable() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let id = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            try await app.test(.POST, "loans", beforeRequest: { req in
                try req.content.encode(CreateLoanDTO(gameID: id, memberID: memberID))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
            })

            try await updateGame(app, id: "\(id)", with: CreateGameDTO(
                title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 120
            )) { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertFalse(try res.content.decode(GameDTO.self).isAvailable)
            }
        }
    }

    func testUpdateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await updateGame(app, id: "\(id)", with: CreateGameDTO(
                title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
            )) { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testUpdateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await updateGame(app, id: "\(id)", with: CreateGameDTO(
                title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
            )) { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testUpdateUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await updateGame(app, id: "\(UUID())", with: CreateGameDTO(
                title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
            )) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testUpdateGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await updateGame(app, id: "not-a-uuid", with: CreateGameDTO(
                title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
            )) { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }
    
    func testDeleteGameReturnsNoContent() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.DELETE, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteGameOnLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let id = try XCTUnwrap(game.id)

            try await insertLoan(
                app, gameID: id, memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(), dueAt: Date()
            )

            try await app.test(.DELETE, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testDeleteGameWithReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let id = try XCTUnwrap(game.id)

            try await insertLoan(
                app, gameID: id, memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(), dueAt: Date(), returnedAt: Date()
            )

            try await app.test(.DELETE, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }

    func testDeleteUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
}
