import Vapor

public func routes(_ app: Application) throws {
    let route = SwiftraRouter(app)
    route.get { req in
        try await view(
            "welcome",
            compact("title", "Swiftra", "message", "It works!"),
            for: req
        )
    }

    route.get("users", use: controller(UserController.self, UserController.webIndex))

    route.group("api") { api in
        let auth = AuthController.self
        api.group("auth") { authRoutes in
            authRoutes.post("register", use: controller(auth, AuthController.register))
            authRoutes.post("login", use: controller(auth, AuthController.login))

            authRoutes.middleware(AuthMiddleware()) { protected in
                protected.get("me", use: controller(auth, AuthController.me))
                protected.post("logout", use: controller(auth, AuthController.logout))
            }
        }

        api.get("users", use: controller(UserController.self, UserController.index))
        api.post("users", use: controller(UserController.self, UserController.store))
        api.get("users", ":id", use: controller(UserController.self, UserController.show))
        api.put("users", ":id", use: controller(UserController.self, UserController.update))
        api.delete("users", ":id", use: controller(UserController.self, UserController.destroy))
    }
}
