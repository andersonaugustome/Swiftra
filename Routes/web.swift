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
        api.middleware(RateLimitMiddleware.api) { limited in
            registerAuthRoutes(on: limited)
            registerUserRoutes(on: limited)
        }
    }
}

private func registerAuthRoutes(on api: SwiftraRouter) {
    let auth = AuthController.self

    api.group("auth") { authRoutes in
        // Endpoints públicos com throttle próprio (configurável via RATE_LIMIT_*).
        authRoutes.middleware(RateLimitMiddleware.auth) { throttled in
            throttled.post("register", use: controller(auth, AuthController.register))
            throttled.post("login", use: controller(auth, AuthController.login))
            throttled.post("refresh", use: controller(auth, AuthController.refresh))
            throttled.post("forgot-password", use: controller(auth, AuthController.forgotPassword))
            throttled.post("reset-password", use: controller(auth, AuthController.resetPassword))
            throttled.post("verify-email", use: controller(auth, AuthController.verifyEmail))
            throttled.post("mfa", "challenge", use: controller(auth, AuthController.mfaChallenge))
        }

        authRoutes.middleware(AuthMiddleware()) { protected in
            protected.get("me", use: controller(auth, AuthController.me))
            protected.post("logout", use: controller(auth, AuthController.logout))
            protected.post("logout-all", use: controller(auth, AuthController.logoutAll))
            protected.post("email", "resend-verification", use: controller(auth, AuthController.resendVerification))
            protected.post("mfa", "setup", use: controller(auth, AuthController.mfaSetup))
            protected.post("mfa", "enable", use: controller(auth, AuthController.mfaEnable))
            protected.post("mfa", "disable", use: controller(auth, AuthController.mfaDisable))
        }
    }
}

private func registerUserRoutes(on api: SwiftraRouter) {
    let users = UserController.self

    // CRUD protegido: exige autenticação; exclusão exige o papel `admin`.
    api.middleware(AuthMiddleware()) { protected in
        protected.get("users", use: controller(users, UserController.index))
        protected.post("users", use: controller(users, UserController.store))
        protected.get("users", ":id", use: controller(users, UserController.show))
        protected.put("users", ":id", use: controller(users, UserController.update))

        protected.middleware(RequireRoleMiddleware("admin")) { admin in
            admin.delete("users", ":id", use: controller(users, UserController.destroy))
        }
    }
}
