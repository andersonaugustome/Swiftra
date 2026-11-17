import App
import Fluent
import Foundation
import Testing
import VaporTesting

@Suite("Eloquent")
struct EloquentTests {
    @Test("Invalid operator, direction and column throw instead of crashing")
    func invalidInputThrows() async throws {
        try await withSwiftraApp { app in
            await #expect(throws: EloquentError.self) {
                try await User.on(app.db).where("email", "~~", "x").get()
            }
            await #expect(throws: EloquentError.self) {
                try await User.on(app.db).orderBy("name", "sideways").get()
            }
            await #expect(throws: EloquentError.self) {
                try await User.on(app.db).where("name; DROP TABLE users", "x").get()
            }
            // Operadores tipados continuam funcionando.
            try await User(name: "Typed", email: "typed@example.com").save(on: app.db)
            let found = try await User.on(app.db).where("email", .equal, "typed@example.com").first()
            #expect(found?.name == "Typed")
            let keyPath = try await User.on(app.db).where(\.$email, "typed@example.com").first()
            #expect(keyPath?.name == "Typed")
            // Superfície tipada completa: sem nenhuma string de coluna.
            #expect(try await User.on(app.db).whereIn(\.$email, ["typed@example.com", "none@example.com"]).count() == 1)
            #expect(try await User.on(app.db).whereNotIn(\.$email, ["typed@example.com"]).count() == 0)
            #expect(try await User.on(app.db).where(\.$name, .like, "Typ").count() == 1)
            #expect(try await User.on(app.db).orderBy(\.$email, .descending).first()?.name == "Typed")
        }
    }

    @Test("Pagination, eager loading, soft deletes and factories")
    func advancedFeatures() async throws {
        try await withSwiftraApp { app in
            let users = try await UserFactory().count(5).createMany(on: app.db)
            let first = try #require(users.first)
            let firstId = try #require(first.id)
            _ = try await PostFactory()
                .count(2)
                .state { $0.$user.id = firstId }
                .createMany(on: app.db)

            let page = try await User.on(app.db).orderBy("name").paginate(page: 2, perPage: 2)
            #expect(page.total == 5)
            #expect(page.data.count == 2)
            #expect(page.currentPage == 2)
            #expect(page.lastPage == 3)
            #expect(page.hasMorePages)

            let simple = try await User.on(app.db).simplePaginate(page: 1, perPage: 2)
            #expect(simple.data.count == 2)
            #expect(simple.hasMorePages)

            // Eager loading declarativo + relação inversa.
            let loaded = try await User.on(app.db)
                .with(\.$posts)
                .where("id", firstId)
                .firstOrFail()
            #expect(loaded.posts.count == 2)
            #expect(loaded.posts.first?.userId == firstId)

            let post = try await Post.on(app.db).with(\.$user).firstOrFail()
            #expect(post.user.id == firstId)

            // Soft delete: some das consultas, volta com withTrashed/restore.
            try await first.delete(on: app.db)
            #expect(try await User.on(app.db).where("id", firstId).first() == nil)
            let trashed = try await User.on(app.db).withTrashed().where("id", firstId).first()
            #expect(trashed?.trashed == true)
            #expect(try await User.on(app.db).onlyTrashed().count() == 1)
            try await trashed?.restore(on: app.db)
            #expect(try await User.on(app.db).where("id", firstId).first() != nil)

            // whereIn / whereNull / pluck / firstOrCreate-like via exists.
            let emails = try await User.on(app.db).orderBy("email").pluck(\.$email)
            #expect(emails.count == 5)
            #expect(try await User.on(app.db).whereIn("id", users.compactMap(\.id)).count() == 5)
            #expect(try await User.on(app.db).whereNull("email_verified_at").count() == 5)
        }
    }

    @Test("Rate limiter blocks after the configured attempts")
    func rateLimiter() async throws {
        let store = RateLimiterStore()
        let now = Date()
        for _ in 0..<3 {
            #expect(await store.hit(key: "test", maxAttempts: 3, decaySeconds: 60, now: now) == nil)
        }
        let blocked = await store.hit(key: "test", maxAttempts: 3, decaySeconds: 60, now: now)
        #expect(blocked != nil)
        #expect((blocked ?? 0) > 0)
    }
}

@Suite("Polymorphic relations")
struct PolymorphicTests {
    @Test("morphMany and morphTo resolve both parent types")
    func morph() async throws {
        try await withSwiftraApp { app in
            let user = User(name: "Morph", email: "morph@example.com")
            try await user.save(on: app.db)
            let post = Post(userId: try #require(user.id), title: "Morph Post")
            try await post.save(on: app.db)

            try await Comment(body: "on user", parent: user).save(on: app.db)
            try await Comment(body: "on post", parent: post).save(on: app.db)
            try await Comment(body: "second on post", parent: post).save(on: app.db)

            #expect(try await user.morphMany(Comment.self, on: app.db).count == 1)
            #expect(try await post.morphMany(Comment.self, on: app.db).count == 2)

            let comment = try #require(try await post.morphMany(Comment.self, on: app.db).first)
            #expect(try await comment.morphParent(Post.self, on: app.db)?.title == "Morph Post")
            #expect(try await comment.morphParent(User.self, on: app.db) == nil)

            let resolved = try await comment.morphParent(on: app.db)
            #expect((resolved as? Post)?.title == "Morph Post")

            // setMorphParent em uma instância existente.
            let moved = Comment(body: "moved")
            try moved.setMorphParent(user)
            try await moved.save(on: app.db)
            #expect(try await user.morphMany(Comment.self, on: app.db).count == 2)
        }
    }
}

@Suite("Database rate limiter")
struct DatabaseRateLimiterTests {
    @Test("Database driver persists windows and blocks over the limit")
    func databaseDriver() async throws {
        try await withSwiftraApp { app in
            for _ in 0..<2 {
                #expect(try await DatabaseRateLimiter.hit(on: app.db, key: "login:test", maxAttempts: 2, decaySeconds: 60) == nil)
            }
            let blocked = try await DatabaseRateLimiter.hit(on: app.db, key: "login:test", maxAttempts: 2, decaySeconds: 60)
            #expect(blocked != nil)
            #expect(try await RateLimitEntry.on(app.db).where("key", "login:test").first()?.attempts == 3)
            #expect(try await DatabaseRateLimiter.remaining(on: app.db, key: "login:test", maxAttempts: 2) == 0)
            // Outra chave não é afetada.
            #expect(try await DatabaseRateLimiter.hit(on: app.db, key: "login:other", maxAttempts: 2, decaySeconds: 60) == nil)
        }
    }
}
