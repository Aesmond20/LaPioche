//
//  UserDTO.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

import Vapor

struct UserDTO: Content {
    let id: UUID?
    let email: String
}

extension User {
    func toDTO() -> UserDTO {
        UserDTO(id: id, email: email)
    }
}
