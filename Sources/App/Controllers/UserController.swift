//
//  UserController.swift
//  App
//
//  Created by Roderic Campbell on 5/6/20.
//

import Vapor
import Authentication

final class UserController {

    func webhooks(_ req: Request) throws -> EventLoopFuture<View> {
        let user = try req.requireAuthenticated(User.self)
        
        return try req.view().render("UserWebhooks", FreshbooksWebhookResponse(name: "roddy"))
    }
}
