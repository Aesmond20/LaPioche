//
//  AuthController.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

import Fluent
import JWT
import Vapor

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
        auth.grouped(UserTokenMiddleware()).get("me", use: me)
    }

    @Sendable
    func register(req: Request) async throws -> Response {
        try CredentialsDTO.validate(content: req)
        let dto = try req.content.decode(CredentialsDTO.self)
        let email = dto.email.lowercased()

        let emailTaken = try await User.query(on: req.db)
            .filter(\.$email == email)
            .count() > 0
        guard !emailTaken else {
            throw Abort(.conflict, reason: "An account with this email already exists")
        }

        let passwordHash = try await req.password.async.hash(dto.password)
        let user = User(email: email, passwordHash: passwordHash)
        try await user.save(on: req.db)
        return try await makeAuthResponse(for: user, req: req).encodeResponse(status: .created, for: req)
    }

    @Sendable
    func login(req: Request) async throws -> AuthResponseDTO {
        let dto = try req.content.decode(CredentialsDTO.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == dto.email.lowercased())
            .first(),
              try await req.password.async.verify(dto.password, created: user.passwordHash)
        else {
            throw Abort(.unauthorized, reason: "Invalid email or password")
        }
        return try await makeAuthResponse(for: user, req: req)
    }

    @Sendable
    func me(req: Request) async throws -> UserDTO {
        try req.auth.require(User.self).toDTO()
    }

    private func makeAuthResponse(for user: User, req: Request) async throws -> AuthResponseDTO {
        let expiresAt = Date().addingTimeInterval(24 * 60 * 60)
        let payload = UserPayload(
            subject: SubjectClaim(value: try user.requireID().uuidString),
            expiration: ExpirationClaim(value: expiresAt)
        )
        let token = try await req.jwt.sign(payload)
        return AuthResponseDTO(token: token, expiresAt: expiresAt, user: user.toDTO())
    }
}
