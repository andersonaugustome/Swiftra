import Vapor

public protocol Controller: Sendable {
    init()
}

public typealias ControllerAction = @Sendable (Request) async throws -> Response

public func controller<C: Controller>(
    _ controller: C.Type,
    _ action: @escaping @Sendable (C) -> @Sendable (Request) async throws -> Response
) -> ControllerAction {
    { request in
        try await action(controller.init())(request)
    }
}

public struct SwiftraRouter {
    private let routes: RoutesBuilder

    public init(_ routes: RoutesBuilder) { self.routes = routes }

    @discardableResult
    public func get(_ path: PathComponent..., use handler: @escaping @Sendable (Request) async throws -> Response) -> Route {
        routes.on(.GET, path, use: handler)
    }

    @discardableResult
    public func post(_ path: PathComponent..., use handler: @escaping @Sendable (Request) async throws -> Response) -> Route {
        routes.on(.POST, path, body: .collect, use: handler)
    }

    @discardableResult
    public func put(_ path: PathComponent..., use handler: @escaping @Sendable (Request) async throws -> Response) -> Route {
        routes.on(.PUT, path, body: .collect, use: handler)
    }

    @discardableResult
    public func delete(_ path: PathComponent..., use handler: @escaping @Sendable (Request) async throws -> Response) -> Route {
        routes.on(.DELETE, path, use: handler)
    }

    public func group(_ prefix: PathComponent..., configure: (SwiftraRouter) throws -> Void) rethrows {
        try configure(SwiftraRouter(routes.grouped(prefix)))
    }

    public func middleware(_ middleware: Middleware..., configure: (SwiftraRouter) throws -> Void) rethrows {
        try configure(SwiftraRouter(routes.grouped(middleware)))
    }
}
