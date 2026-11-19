@testable import App
import XCTVapor

final class MemberTests: XCTestCase {
    private func updateMember(
        _ app: Application,
        id: String,
        with dto: CreateMemberDTO,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.testAuthorized(.PUT, "members/\(id)", beforeRequest: { req in
            try req.content.encode(dto)
        }, afterResponse: afterResponse)
    }
    
    func testCreateMemberReturnsCreated() async throws {
        try await withApp { app in
            try await app.testAuthorized(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }

    func testCreateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await app.testAuthorized(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app)

            try await app.testAuthorized(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Autre", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testShowUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.testAuthorized(.GET, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testUpdateMemberReturnsUpdatedMember() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await updateMember(app, id: "\(id)", with: CreateMemberDTO(
                name: "Camille Martin", email: "camille.martin@example.com"
            )) { res in
                XCTAssertEqual(res.status, .ok)
                let updated = try res.content.decode(MemberDTO.self)
                XCTAssertEqual(updated.id, id)
                XCTAssertEqual(updated.name, "Camille Martin")
                XCTAssertEqual(updated.email, "camille.martin@example.com")
            }

            try await app.testAuthorized(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille Martin")
            })
        }
    }

    func testUpdateMemberKeepingOwnEmailSucceeds() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await updateMember(app, id: "\(id)", with: CreateMemberDTO(
                name: "Camille Martin", email: "camille@example.com"
            )) { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille Martin")
            }
        }
    }

    func testUpdateMemberWithEmailOfAnotherMemberReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app, name: "Alex", email: "alex@example.com")
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await updateMember(app, id: "\(id)", with: CreateMemberDTO(
                name: "Camille", email: "alex@example.com"
            )) { res in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    func testUpdateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await updateMember(app, id: "\(id)", with: CreateMemberDTO(
                name: "Camille", email: "not-an-email"
            )) { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testUpdateMemberWithEmptyNameIsRejected() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await updateMember(app, id: "\(id)", with: CreateMemberDTO(
                name: "", email: "camille@example.com"
            )) { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testUpdateUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await updateMember(app, id: "\(UUID())", with: CreateMemberDTO(
                name: "Camille", email: "camille@example.com"
            )) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testUpdateMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await updateMember(app, id: "not-a-uuid", with: CreateMemberDTO(
                name: "Camille", email: "camille@example.com"
            )) { res in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }
    
    func testDeleteMemberReturnsNoContent() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.testAuthorized(.DELETE, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.testAuthorized(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteMemberWithLoanInProgressReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await insertLoan(
                app, gameID: try XCTUnwrap(game.id), memberID: id,
                borrowedAt: Date(), dueAt: Date()
            )

            try await app.testAuthorized(.DELETE, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testDeleteMemberWithReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await insertLoan(
                app, gameID: try XCTUnwrap(game.id), memberID: id,
                borrowedAt: Date(), dueAt: Date(), returnedAt: Date()
            )

            try await app.testAuthorized(.DELETE, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })

            try await app.testAuthorized(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }

    func testDeleteUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.testAuthorized(.DELETE, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.testAuthorized(.DELETE, "members/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testListMemberLoansReturnsAllLoansFromOldestToNewest() async throws {
        try await withApp { app in
            let firstGame = try await createGame(app, title: "Catan")
            let secondGame = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)
            let other = try await createMember(app, name: "Alex", email: "alex@example.com")
            let memberID = try XCTUnwrap(member.id)
            let firstGameID = try XCTUnwrap(firstGame.id)
            let secondGameID = try XCTUnwrap(secondGame.id)

            try await insertLoan(
                app, gameID: firstGameID, memberID: memberID,
                borrowedAt: Date(timeIntervalSinceNow: -30 * 86_400),
                dueAt: Date(timeIntervalSinceNow: -16 * 86_400),
                returnedAt: Date(timeIntervalSinceNow: -20 * 86_400)
            )
            try await insertLoan(
                app, gameID: secondGameID, memberID: memberID,
                borrowedAt: Date(timeIntervalSinceNow: -2 * 86_400),
                dueAt: Date(timeIntervalSinceNow: 12 * 86_400)
            )
            try await insertLoan(
                app, gameID: firstGameID, memberID: try XCTUnwrap(other.id),
                borrowedAt: Date(), dueAt: Date(timeIntervalSinceNow: 14 * 86_400)
            )

            try await app.testAuthorized(.GET, "members/\(memberID)/loans", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let loans = try res.content.decode([LoanDTO].self)
                XCTAssertEqual(loans.count, 2)
                XCTAssertTrue(loans.allSatisfy { $0.memberID == memberID })
                XCTAssertEqual(loans.first?.gameID, firstGameID)
                XCTAssertNotNil(loans.first?.returnedAt)
                XCTAssertEqual(loans.last?.gameID, secondGameID)
                XCTAssertNil(loans.last?.returnedAt)
            })
        }
    }

    func testListMemberLoansWithoutLoansReturnsEmptyList() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await app.testAuthorized(.GET, "members/\(memberID)/loans", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([LoanDTO].self).count, 0)
            })
        }
    }

    func testListLoansOfUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.testAuthorized(.GET, "members/\(UUID())/loans", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testListLoansWithMalformedMemberIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.testAuthorized(.GET, "members/not-a-uuid/loans", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
}
