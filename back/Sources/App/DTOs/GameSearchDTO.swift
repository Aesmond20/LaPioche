//
//  GameSearchDTO.swift
//  LaPioche
//
//  Created by Aesmond on 18/11/2026.
//

import Vapor

struct GameSearchDTO: Content, Validatable {
    let q: String?
    let players: Int?
    let maxDuration: Int?
    
    static func validations(_ validations: inout Validations) {
        validations.add("players", as: Int.self, is: .range(1...), required: false)
        validations.add("maxDuration", as: Int.self, is: .range(1...), required: false)
    }
}
