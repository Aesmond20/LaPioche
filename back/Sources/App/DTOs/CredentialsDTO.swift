//
//  CredentialsDTO.swift
//  LaPioche
//
//  Created by Aesmond on 19/11/2026.
//

import Vapor

struct CredentialsDTO: Content, Validatable {
    let email: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
    }
}
