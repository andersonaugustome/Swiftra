import Fluent
import Vapor

public struct UserController: Controller {
    public init() {}

    /// Lista paginada no formato do Laravel: `?page=1&per_page=15`.
    public func index(req: Request) async throws -> Response {
        let page = max(req.query[Int.self, at: "page"] ?? 1, 1)
        let perPage = min(max(req.query[Int.self, at: "per_page"] ?? 15, 1), 100)
        let search = req.query[String.self, at: "search"]

        var query = User.orderBy("name")
        if let search, !search.isEmpty {
            query = query.where("name", "like", search)
        }
        let users = try await query.paginate(page: page, perPage: perPage)
        return try await users.map { UserResource($0) }.encodeResponse(for: req)
    }

    public func webIndex(req: Request) async throws -> Response {
        let users = try await User.orderBy("name").get()
        return try await view(
            "users.index",
            compact(("title", "Usuários"), ("users", users), ("total", users.count)),
            for: req
        )
    }

    public func store(req: Request) async throws -> Response {
        let input = try req.content.decode(UserInput.self)
        try validate(input)
        guard try await User.where("email", input.email).first() == nil else {
            throw Abort(.conflict, reason: "Email already exists")
        }
        let user = User(name: input.name, email: input.email)
        try await user.save()
        return try await UserResource(user).encodeResponse(status: .created, for: req)
    }

    public func show(req: Request) async throws -> Response {
        try await UserResource(try await find(req)).encodeResponse(for: req)
    }

    public func update(req: Request) async throws -> Response {
        let input = try req.content.decode(UserInput.self)
        try validate(input)
        let user = try await find(req)
        if let existing = try await User.where("email", input.email).first(), existing.id != user.id {
            throw Abort(.conflict, reason: "Email already exists")
        }
        user.name = input.name
        user.email = input.email
        try await user.save()
        return try await UserResource(user).encodeResponse(for: req)
    }

    public func destroy(req: Request) async throws -> Response {
        let user = try await find(req)
        try await user.delete()
        return Response(status: .noContent)
    }

    private func find(_ req: Request) async throws -> User {
        guard let id = req.parameters.get("id", as: UUID.self), let user = try await User.find(id) else {
            throw Abort(.notFound, reason: "User not found")
        }
        return user
    }

    private func validate(_ input: UserInput) throws {
        guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.email.contains("@") else {
            throw Abort(.unprocessableEntity, reason: "A valid name and email are required")
        }
    }
}

public struct UserInput: Content {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}
