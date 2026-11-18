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
    
    private func searchGames(
        _ app: Application,
        query: String,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.GET, "games?\(query)", afterResponse: afterResponse)
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
    
    func testSearchGamesByTitleIgnoresCase() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await searchGames(app, query: "q=CAT") { res in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.map(\.title), ["Catan"])
            }
        }
    }

    func testSearchGamesByPlayerCount() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan", minPlayers: 3, maxPlayers: 4)
            _ = try await createGame(app, title: "Dixit", minPlayers: 3, maxPlayers: 6)
            _ = try await createGame(app, title: "Patchwork", minPlayers: 2, maxPlayers: 2)

            try await searchGames(app, query: "players=5") { res in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.map(\.title), ["Dixit"])
            }
        }
    }

    func testSearchGamesByMaxDurationIncludesEqualDuration() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan", durationMinutes: 90)
            _ = try await createGame(app, title: "Dixit", durationMinutes: 30)

            try await searchGames(app, query: "maxDuration=30") { res in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.map(\.title), ["Dixit"])
            }
        }
    }

    func testSearchGamesCombinesAllParameters() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90)
            _ = try await createGame(app, title: "Azul", minPlayers: 2, maxPlayers: 4, durationMinutes: 45)
            _ = try await createGame(app, title: "Dixit", minPlayers: 3, maxPlayers: 6, durationMinutes: 30)

            try await searchGames(app, query: "q=a&players=4&maxDuration=60") { res in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.map(\.title), ["Azul"])
            }
        }
    }

    func testSearchGamesWithoutResultsReturnsEmptyList() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")

            try await searchGames(app, query: "q=zzz") { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 0)
            }
        }
    }

    func testSearchGamesWithZeroPlayersIsRejected() async throws {
        try await withApp { app in
            try await searchGames(app, query: "players=0") { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testSearchGamesWithNegativeMaxDurationIsRejected() async throws {
        try await withApp { app in
            try await searchGames(app, query: "maxDuration=-10") { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testSearchGamesWithNonIntegerPlayersIsRejected() async throws {
        try await withApp { app in
            try await searchGames(app, query: "players=abc") { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }
    
    func testFilterAvailableGamesIncludesReturnedGames() async throws {
        try await withApp { app in
            let free = try await createGame(app, title: "Azul")
            let borrowed = try await createGame(app, title: "Catan")
            let returned = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await insertLoan(
                app, gameID: try XCTUnwrap(borrowed.id), memberID: memberID,
                borrowedAt: Date(), dueAt: Date(timeIntervalSinceNow: 14 * 86_400)
            )
            try await insertLoan(
                app, gameID: try XCTUnwrap(returned.id), memberID: memberID,
                borrowedAt: Date(timeIntervalSinceNow: -20 * 86_400),
                dueAt: Date(timeIntervalSinceNow: -6 * 86_400),
                returnedAt: Date(timeIntervalSinceNow: -7 * 86_400)
            )

            try await searchGames(app, query: "available=true") { res in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.map(\.title).sorted(), ["Azul", "Dixit"])
                XCTAssertTrue(games.allSatisfy(\.isAvailable))
                XCTAssertTrue(games.contains { $0.id == free.id })
            }
        }
    }

    func testFilterUnavailableGamesReturnsOnlyBorrowedGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Azul")
            let borrowed = try await createGame(app, title: "Catan")
            let member = try await createMember(app)

            try await insertLoan(
                app, gameID: try XCTUnwrap(borrowed.id), memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(), dueAt: Date(timeIntervalSinceNow: 14 * 86_400)
            )

            try await searchGames(app, query: "available=false") { res in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.map(\.title), ["Catan"])
                XCTAssertFalse(try XCTUnwrap(games.first).isAvailable)
            }
        }
    }

    func testFilterAvailableCombinesWithSearchParameters() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            let borrowed = try await createGame(app, title: "Catan Junior")
            _ = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)

            try await insertLoan(
                app, gameID: try XCTUnwrap(borrowed.id), memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(), dueAt: Date(timeIntervalSinceNow: 14 * 86_400)
            )

            try await searchGames(app, query: "q=catan&available=true") { res in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.map(\.title), ["Catan"])
            }
        }
    }

    func testFilterAvailableWithInvalidValueIsRejected() async throws {
        try await withApp { app in
            try await searchGames(app, query: "available=maybe") { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }
}
