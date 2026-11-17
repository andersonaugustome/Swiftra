import Fluent
import Foundation
import Vapor

/// Relações polimórficas no estilo `morphMany`/`morphTo` do Laravel.
///
/// O Fluent não tem polimorfismo nativo; esta camada adiciona a convenção
/// `<relation>_type` + `<relation>_id` com um registro de tipos:
///
/// ```swift
/// // Em configure.swift (já feito para User/Post):
/// MorphRegistry.register(User.self)
/// MorphRegistry.register(Post.self)
///
/// let comments = try await post.morphMany(Comment.self, on: database)
/// let author = try await comment.morphParent(User.self, on: database)
/// let anyParent = try await comment.morphParent(on: database) // (any PolymorphicParent)?
/// ```

/// Lado "pai" de uma relação polimórfica.
public protocol PolymorphicParent: EloquentModel {
    /// Valor gravado na coluna `*_type`. Padrão: nome da model.
    static var morphType: String { get }
}

public extension PolymorphicParent {
    static var morphType: String { String(describing: Self.self) }
}

/// Lado "filho": a model que carrega `*_type`/`*_id`.
///
/// As colunas concretas ficam na sua migration; o protocolo só exige os
/// acessores tipados para a camada montar as consultas.
public protocol PolymorphicChild: EloquentModel {
    var morphTypeValue: String { get set }
    var morphIDValue: UUID { get set }
    static var morphTypeField: String { get }
    static var morphIDField: String { get }
}

public extension PolymorphicChild {
    static var morphTypeField: String { "commentable_type" }
    static var morphIDField: String { "commentable_id" }
}

// MARK: - morphMany / morphTo

public extension PolymorphicParent {
    /// Todos os filhos que apontam para esta model: `morphMany(Comment.self)`.
    func morphMany<Child: PolymorphicChild>(
        _ child: Child.Type,
        on database: any Database
    ) async throws -> [Child] {
        try await Child.on(database)
            .where(Child.morphTypeField, Self.morphType)
            .where(Child.morphIDField, try requireID())
            .get()
    }

    /// Query encadeável equivalente, para filtrar/ordenar/paginar.
    func morphManyQuery<Child: PolymorphicChild>(
        _ child: Child.Type,
        on database: any Database
    ) throws -> EloquentQuery<Child> {
        Child.on(database)
            .where(Child.morphTypeField, Self.morphType)
            .where(Child.morphIDField, try requireID())
    }
}

public extension PolymorphicChild {
    /// Atribui o pai polimórfico antes de salvar.
    func setMorphParent<Parent: PolymorphicParent>(_ parent: Parent) throws where Parent.IDValue == UUID {
        morphTypeValue = Parent.morphType
        morphIDValue = try parent.requireID()
    }

    /// Resolve o pai quando o tipo é conhecido em compilação.
    func morphParent<Parent: PolymorphicParent>(
        _ parent: Parent.Type,
        on database: any Database
    ) async throws -> Parent? where Parent.IDValue == UUID {
        guard morphTypeValue == Parent.morphType else { return nil }
        return try await Parent.find(morphIDValue, on: database)
    }

    /// Resolve o pai pelo registro de tipos, sem conhecer o tipo concreto.
    func morphParent(on database: any Database) async throws -> (any PolymorphicParent)? {
        try await MorphRegistry.shared.resolve(type: morphTypeValue, id: morphIDValue, on: database)
    }
}

// MARK: - Registro de tipos

public final class MorphRegistry: @unchecked Sendable {
    public static let shared = MorphRegistry()

    private var resolvers: [String: (UUID, any Database) async throws -> (any PolymorphicParent)?] = [:]
    private let lock = NSLock()

    public init() {}

    public func register<Parent: PolymorphicParent>(_ parent: Parent.Type) where Parent.IDValue == UUID {
        lock.withLock {
            resolvers[Parent.morphType] = { id, database in
                try await Parent.find(id, on: database)
            }
        }
    }

    public func resolve(type: String, id: UUID, on database: any Database) async throws -> (any PolymorphicParent)? {
        let resolver = lock.withLock { resolvers[type] }
        return try await resolver?(id, database)
    }

    public static func register<Parent: PolymorphicParent>(_ parent: Parent.Type) where Parent.IDValue == UUID {
        shared.register(parent)
    }
}
