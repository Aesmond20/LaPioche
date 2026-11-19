//
//  UserPayload.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

import JWT

struct UserPayload: JWTPayload {
    var subject: SubjectClaim
    var expiration: ExpirationClaim

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try expiration.verifyNotExpired()
    }
}
