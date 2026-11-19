//
//  AuthResponseDTO.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

import Vapor

struct AuthResponseDTO: Content {
    let token: String
    let expiresAt: Date
    let user: UserDTO
}
