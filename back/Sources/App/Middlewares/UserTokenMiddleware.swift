//
//  UserTokenMiddleware.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

import Fluent
import JWT
import Vapor

struct UserTokenMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let payload: UserPayload
        do {
            payload = try await request.jwt.verify(as: UserPayload.self)
        } catch {
            throw Abort(.unauthorized, reason: "Authentication required")
        }

        guard let userID = UUID(uuidString: payload.subject.value),
              let user = try await User.find(userID, on: request.db)
        else {
            throw Abort(.unauthorized, reason: "Authentication required")
        }

        request.auth.login(user)
        return try await next.respond(to: request)
    }
}
