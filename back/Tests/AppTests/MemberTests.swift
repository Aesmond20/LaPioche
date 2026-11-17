@testable import App
import XCTVapor

final class MemberTests: XCTestCase {
    private func updateMember(
        _ app: Application,
        id: String,
        with dto: CreateMemberDTO,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
            try req.content.encode(dto)
        }, afterResponse: afterResponse)
    }
    
    func testCreateMemberReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }

    func testCreateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app)

            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Autre", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testShowUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/\(UUID())", afterResponse: { res async throws in
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

            try await app.test(.GET, "members/\(id)", afterResponse: { res async throws in
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

            try await app.test(.DELETE, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.test(.GET, "members/\(id)", afterResponse: { res async throws in
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

            try await app.test(.DELETE, "members/\(id)", afterResponse: { res async throws in
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

            try await app.test(.DELETE, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })

            try await app.test(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }

    func testDeleteUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "members/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
}
