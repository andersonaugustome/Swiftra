# Swiftra

Swiftra é um scaffold de framework server-side escrito em Swift 6, construído sobre Vapor e Fluent. O projeto oferece uma organização familiar para aplicações web, rotas concisas, controllers assíncronos, views HTML, uma camada de consultas fluente, migrations, autenticação Bearer e CLI.

> Estado atual: scaffold completo inspirado no Laravel — SwiftBlade com layouts/diretivas/componentes, Eloquent com paginação/eager loading/soft deletes/factories e autenticação com refresh tokens, MFA, papéis e permissões. Veja [Limitações atuais](#limitações-atuais) para o que foi corrigido e as decisões conscientes do scaffold.

## Sumário

- [Recursos](#recursos)
- [Requisitos](#requisitos)
- [Início rápido](#início-rápido)
- [Configuração](#configuração)
- [Bancos de dados](#bancos-de-dados)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Inicialização da aplicação](#inicialização-da-aplicação)
- [Rotas](#rotas)
- [Controllers](#controllers)
- [Views e SwiftBlade](#views-e-swiftblade)
- [Models e Eloquent](#models-e-eloquent)
- [Joins](#joins)
- [Migrations](#migrations)
- [Autenticação](#autenticação)
- [Middleware](#middleware)
- [CLI](#cli)
- [API de exemplo](#api-de-exemplo)
- [Testes](#testes)
- [Produção](#produção)
- [Solução de problemas](#solução-de-problemas)
- [Limitações atuais](#limitações-atuais)

## Recursos

- Swift 6 com concorrência `async/await`.
- Vapor como infraestrutura HTTP, console, middleware e codificação de conteúdo.
- `SwiftraRouter` com `get`, `post`, `put`, `delete`, `group` e `middleware`.
- Controllers chamados diretamente nas rotas com verificação de tipos.
- Helpers `view` e `compact`.
- SwiftBlade com `{{ }}` escapado, `{!! !!}` cru, layouts (`@extends/@section/@yield`), `@if/@foreach/@forelse/@switch`, `@include`, componentes (`<x-...>` e `@component`), `@push/@stack`, `@auth/@guest`, `@csrf` e `@method`.
- Fluent com API Eloquent: `where` (string, tipado e por key path), `whereIn`, `whereNull`, `whereBetween`, `orWhere`, `orderBy`, `limit`, `find`, `firstOrFail`, `get`, `count`, `exists`, `save`, `delete`, `chunk` e `when`.
- Paginação no formato do Laravel (`paginate`/`simplePaginate`), eager loading declarativo (`with(\.$posts)`), soft deletes, factories e joins com até duas models relacionadas.
- `join` e `leftJoin` com retorno das models participantes.
- SQLite para desenvolvimento e testes; MySQL real na suíte de integração e no CI.
- Migrations assíncronas.
- Autenticação com BCrypt, access tokens curtos configuráveis, refresh tokens rotativos com detecção de reuso, recuperação de senha, verificação de email, MFA TOTP e papéis/permissões.
- Rate limiting configurável nos endpoints de autenticação e na API.
- CLI com servidor, migrations, seed, listagem de rotas e geradores (controller, model, migration, factory).
- CRUD JSON de `User` protegido por autenticação (exclusão exige papel `admin`) e relacionamento de exemplo com `Post`.

## Requisitos

- Swift 6 ou superior.
- macOS 14+ ou uma distribuição Linux compatível com Vapor.
- MySQL somente se `DB_CONNECTION=mysql` for usado.
- Acesso à internet no primeiro build para resolver os pacotes Swift.

Confirme o ambiente:

```bash
swift --version
```

## Início rápido

```bash
cp .env.example .env
swift build
swift run Swiftra migrate
swift run Swiftra serve
```

A aplicação ficará disponível em:

```text
http://127.0.0.1:8080
```

Verifique as rotas registradas:

```bash
swift run Swiftra route:list
```

## Configuração

A Swiftra carrega `.env` no início da aplicação. Variáveis já definidas no processo têm precedência e não são sobrescritas pelo arquivo.

Crie o arquivo local a partir do exemplo:

```bash
cp .env.example .env
```

Variáveis disponíveis:

| Variável | Padrão | Finalidade |
|---|---:|---|
| `APP_ENV` | `development` no exemplo | Variável reservada; o scaffold atual não a aplica a `Environment.detect()`. |
| `APP_HOST` | `127.0.0.1` | Host usado pelo servidor HTTP. |
| `APP_PORT` | `8080` | Porta usada pelo servidor HTTP. |
| `DB_CONNECTION` | `sqlite` | Driver: `sqlite` ou `mysql`. |
| `DB_PATH` | `swiftra.sqlite` | Arquivo SQLite. |
| `DB_HOST` | `127.0.0.1` | Host do MySQL. |
| `DB_PORT` | `3306` | Porta do MySQL. |
| `DB_DATABASE` | `swiftra` | Banco MySQL. |
| `DB_USERNAME` | `root` | Usuário MySQL. |
| `DB_PASSWORD` | vazio | Senha MySQL. |
| `DB_TLS` | `disabled` | `required` exige TLS verificado no MySQL. |
| `AUTH_ACCESS_TOKEN_TTL_MINUTES` | `60` | Vida do access token. |
| `AUTH_REFRESH_TOKEN_TTL_DAYS` | `30` | Vida do refresh token. |
| `AUTH_REQUIRE_VERIFIED_EMAIL` | `false` | Exige email verificado no login. |
| `RATE_LIMIT_AUTH_MAX` / `RATE_LIMIT_API_MAX` | `10` / `120` | Tentativas por janela e IP. |

O arquivo `.env` está ignorado pelo Git. Não publique credenciais reais.

Também é possível sobrescrever host e porta pela CLI:

```bash
swift run Swiftra serve --hostname 0.0.0.0 --port 8081
```

## Bancos de dados

### SQLite

SQLite é o padrão e não exige um servidor externo:

```env
DB_CONNECTION=sqlite
DB_PATH=swiftra.sqlite
```

Prepare as tabelas:

```bash
swift run Swiftra migrate
```

### MySQL

Crie o banco com UTF-8 completo:

```sql
CREATE DATABASE swiftra
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
```

Configure o `.env`:

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=swiftra
DB_USERNAME=root
DB_PASSWORD=sua_senha
```

Opcionalmente, suba um MySQL local com `docker compose up -d mysql`. `DB_TLS=disabled` (padrão) atende servidores locais/docker; em produção use `DB_TLS=required` com certificado válido.

Execute as migrations e inicie o servidor:

```bash
swift run Swiftra migrate
swift run Swiftra serve
```

Para validar contra o servidor real, `./scripts/test-mysql.sh` roda a suíte de integração (banco `swiftra_test`, usuário `DB_USERNAME`/`DB_PASSWORD` do ambiente).

Models, consultas, joins, autenticação e migrations usam Fluent. Os controllers não precisam ser modificados ao trocar SQLite por MySQL.

Durante os testes, a aplicação força SQLite em memória, independentemente do `.env`.

## Estrutura do projeto

```text
.
├── App/
│   ├── Auth/                  # Auth, tokens, MFA TOTP, papéis/permissões, rate limiting
│   ├── Console/               # Comandos da CLI
│   ├── Database/              # Camada Eloquent e contexto de banco
│   ├── Http/Controllers/      # Controllers HTTP
│   ├── Models/                # Models Fluent
│   ├── Routing/               # SwiftraRouter e adaptação de controllers
│   ├── Support/               # .env, view e compact
│   ├── Views/                 # Engine SwiftBlade (parser, expressões, layouts)
│   └── configure.swift        # Configuração central
├── Config/                    # Configurações versionadas
├── Database/Migrations/       # Migrations
├── Resources/Views/           # Templates .blade.html
├── Routes/web.swift           # Rotas web e API
├── Run/main.swift             # Executável
├── Tests/AppTests/            # Testes funcionais
└── Package.swift              # Pacote e dependências
```

O target `App` inclui `App/`, `Routes/` e `Database/`. O executável `Swiftra` fica em `Run/`.

## Inicialização da aplicação

O fluxo principal está em `App/configure.swift`:

1. Carrega `.env`.
2. Seleciona SQLite ou MySQL.
3. Configura host e porta HTTP.
4. Registra migrations.
5. Registra o SwiftBlade.
6. Registra middleware global.
7. Registra comandos.
8. Registra rotas.

Ao criar uma migration, um middleware global ou um novo provider, registre-o nesse arquivo.

## Rotas

As rotas são declaradas em `Routes/web.swift` com `SwiftraRouter`:

```swift
import Vapor

public func routes(_ app: Application) throws {
    let route = SwiftraRouter(app)

    route.get { req in
        Response(status: .ok, body: .init(string: "Hello"))
    }

    route.get("health") { req in
        try await ["status": "ok"].encodeResponse(for: req)
    }
}
```

### Métodos HTTP

```swift
route.get("posts", use: handler)
route.post("posts", use: handler)
route.put("posts", ":id", use: handler)
route.delete("posts", ":id", use: handler)
```

Os métodos `post` e `put` coletam o corpo da requisição antes de chamar o handler.

### Parâmetros

```swift
route.get("posts", ":id") { req in
    guard let id = req.parameters.get("id", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    return try await ["id": id.uuidString].encodeResponse(for: req)
}
```

### Grupos e prefixos

```swift
route.group("api") { api in
    api.group("v1") { v1 in
        v1.get("users", use: controller(UserController.self, UserController.index))
    }
}
```

### Grupos com middleware

```swift
route.middleware(AuthMiddleware()) { authenticated in
    authenticated.get("profile") { req in
        try await UserResource(try Auth.requireUser()).encodeResponse(for: req)
    }
}
```

### Listagem

```bash
swift run Swiftra route:list
```

## Controllers

Controllers implementam `Controller`, são `Sendable`, possuem `init()` e retornam `Response`:

```swift
import Vapor

struct PostController: Controller {
    init() {}

    func index(req: Request) async throws -> Response {
        let posts = try await Post.orderBy("created_at", "desc").get()
        return try await posts.encodeResponse(for: req)
    }
}
```

Registre o método sem instanciar o controller manualmente:

```swift
route.get("posts", use: controller(PostController.self, PostController.index))
```

### Conteúdo JSON

Tipos de entrada conformam a `Content`:

```swift
struct StorePostInput: Content {
    let userId: UUID
    let title: String
}

func store(req: Request) async throws -> Response {
    let input = try req.content.decode(StorePostInput.self)
    let post = Post(userId: input.userId, title: input.title)
    try await post.save()
    return try await post.encodeResponse(status: .created, for: req)
}
```

Use `Abort` para respostas de erro:

```swift
throw Abort(.notFound, reason: "Post not found")
```

## Views e SwiftBlade

Templates ficam em `Resources/Views/` e usam a extensão `.blade.html`.

```html
<!doctype html>
<html lang="pt-BR">
<head><title>{{ title }}</title></head>
<body>
    <h1>{{ title }}</h1>
    <p>{{ user.name }}</p>
</body>
</html>
```

Retorne uma view pelo controller:

```swift
func index(req: Request) async throws -> Response {
    let users = try await User.orderBy("name").get()

    return try await view(
        "users.index",
        compact("title", "Usuários", "users", users),
        for: req
    )
}
```

O nome `users.index` resolve para:

```text
Resources/Views/users/index.blade.html
```

`compact` não tem limite de pares. Formas aceitas:

```swift
compact("user", user)
compact("title", title, "user", user, "active", true)   // overloads posicionais (até 6)
// Ilimitada, recomendada:
compact(("title", "Usuários"), ("users", users), ("total", total))
// Ou o atalho estilo Laravel:
view("users.index", with: ["users": users], for: req)
```

Valores interpolados com `{{ }}` são escapados para HTML; `{!! !!}` imprime sem escapar. Uma chave ausente resulta em string vazia.

### Diretivas do SwiftBlade

```blade
@extends('layouts.app')

@section('content')
  @if(user) Olá, {{ user.name }} @else Convidado @endif
  @foreach(users as user)
    {{ loop.iteration }}. {{ user.name }} ({{ user.email }})
  @empty
    Nenhum usuário.
  @endforeach
  @include('partials.footer')
  <x-alert type="success">Salvo!</x-alert>
@endsection
```

Suportadas: `@swift` (declarações `let`/`var` no template), `@if/@elseif/@else`, `@unless`, `@isset`, `@empty`, `@foreach` (`users as user`, `key => user` ou `user in users`, com `loop.index/iteration/first/last/count`), `@forelse`, `@switch/@case/@default/@break`, `@break/@continue`, `@extends/@section/@yield/@parent`, `@include` (com dados extras), `@component`, `<x-nome>` com atributos (`:prop` amarrado) e `<x-slot>`, `@push/@stack`, `@auth/@guest`, `@csrf`, `@method('PUT')`, comentários `{{-- --}}` e `@verbatim`. Expressões aceitam comparações, `&&`/`||`/`!`, `??`, ternário, funções como `count()`, `upper()` e `isset()` e métodos sobre valores (`user.name.uppercased()`, `items.count()`, `tags.join(', ')`, encadeados). `@parent` funciona em cadeias de layouts com qualquer profundidade.

Código no template usa a sintaxe Swift, sem `$` nem PHP:

```blade
@swift
  let total = count(users)
  var titulo = "Usuários"
@endswift

<h1>{{ titulo }}</h1>
<p>{{ total }} registro(s).</p>

{{-- Forma curta, em uma linha: --}}
@swift(let dobro = total * 2)
```

## Models e Eloquent

Uma model implementa `EloquentModel` e pode também implementar `Content` para entrada/saída HTTP:

```swift
import Fluent
import Vapor

final class Post: SoftDeletableModel, Content, @unchecked Sendable {
    static let schema = "posts"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User          // relação declarativa
    @Field(key: "title") var title: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    init() {}

    init(id: UUID? = nil, userId: UUID, title: String) {
        self.id = id
        self.$user.id = userId
        self.title = title
    }
}

// Em User:  @Children(for: \Post.$user) var posts: [Post]
```

### Consultas dentro de requests

`EloquentMiddleware` disponibiliza automaticamente o banco durante uma requisição:

```swift
let users = try await User.get()
let first = try await User.first()
let user = try await User.find(id)
```

### Consultas fora de requests

Jobs, comandos e testes precisam iniciar a consulta com `.on(database)`:

```swift
let users = try await User.on(database)
    .orderBy("name")
    .get()
```

Chamar `User.where(...)` fora do contexto de request, sem `.on(database)`, encerra a execução com uma mensagem de precondição.

### Where e operadores

```swift
let user = try await User.where("email", email).first()

let users = try await User
    .where("name", "like", "Taylor")
    .where("created_at", ">=", startDate)
    .orderBy("name", "asc")
    .limit(20)
    .get()
```

Operadores aceitos:

| Operador | Significado |
|---|---|
| `=` ou `==` | Igual |
| `!=` ou `<>` | Diferente |
| `>` | Maior que |
| `>=` | Maior ou igual |
| `<` | Menor que |
| `<=` | Menor ou igual |
| `like` | Contém |
| `not like` | Não contém |

Operadores desconhecidos, colunas inválidas e direções inválidas **não** derrubam o processo: a query registra um `EloquentError` e o primeiro método terminal (`get`, `first`, `count`, `paginate`...) o lança. Para verificação em compilação, use os operadores tipados ou key paths:

```swift
User.where("email", .equal, email)     // QueryOperator
User.where(\.$email, email)           // key path Fluent
```

As direções aceitas são `asc`, `ascending`, `desc`, `descending` — ou `SortDirection` / `.descending` tipados.

### Where in

```swift
let users = try await User
    .whereIn("status", ["active", "pending"])
    .get()
```

### Resultados

```swift
let users = try await User.get()                         // [User]
let user = try await User.where("email", email).first() // User?
let user = try await User.where("id", id).firstOrFail() // User ou HTTP 404
let total = try await User.where("active", true).count()
let exists = try await User.where("email", email).exists()
```

### Persistência

```swift
let user = User(name: "Taylor", email: "taylor@example.com")
try await user.save()

user.name = "Taylor Updated"
try await user.save()

try await user.delete()
```

Dentro de jobs ou comandos, use as APIs Fluent explícitas:

```swift
try await user.save(on: database)
try await user.delete(on: database)
```

### Key paths Fluent

As versões type-safe continuam disponíveis no builder:

```swift
let user = try await User.query()
    .where(\.$email, email)
    .orderBy(\.$name)
    .first()
```

### Paginação

```swift
let page = try await User.orderBy("name").paginate(page: 1, perPage: 15)
// Paginator<User>: data, current_page, per_page, total, last_page,
// from, to, has_more_pages  (formato do LengthAwarePaginator)

let simple = try await User.simplePaginate(page: 1, perPage: 15) // sem count
```

`GET /api/users?page=1&per_page=15&search=ana` usa essa paginação.

### Eager loading e relações declarativas

```swift
let users = try await User.with(\.$posts).get()        // sem N+1
let post = try await Post.with(\.$user).firstOrFail()
```

### Soft deletes

Models `SoftDeletableModel` (com `@Timestamp(key: "deleted_at", on: .delete)`) somem das consultas ao apagar. Use `withTrashed()`, `onlyTrashed()`, `restore()`/`restoreAll()` e `forceDelete()` para o ciclo completo.

### Factories

```swift
let users = try await UserFactory().count(3).createMany(on: database)
let admin = try await UserFactory().state { $0.name = "Admin" }.create(on: database)
```

Crie novas com `swift run Swiftra make:factory NomeFactory`.

### Relações polimórficas

```swift
MorphRegistry.register(User.self) // em configure.swift

let comments = try await post.morphMany(Comment.self, on: database)
let parent = try await comment.morphParent(Post.self, on: database)
let anyParent = try await comment.morphParent(on: database) // via registro
```

### Acesso total ao Fluent

`query.fluentQuery` expõe o `QueryBuilder` do Fluent — toda a API dele (`group`, `set`, aggregates...) continua acessível quando a camada Eloquent não basta.

## Joins

Swift precisa conhecer o tipo da tabela relacionada. Por isso, a model associada é o primeiro argumento.

### Inner join

```swift
let rows = try await User
    .join(Post.self, "posts.user_id", "=", "users.id")
    .where("posts.title", "like", "Swift")
    .orderBy("users.name")
    .getJoined(Post.self)

for row in rows {
    print(row.base.name)
    print(row.joined.title)
}
```

O operador `=` pode ser omitido:

```swift
let rows = try await User
    .join(Post.self, "posts.user_id", "users.id")
    .getJoined(Post.self)
```

### Left join

```swift
let rows = try await User
    .leftJoin(Post.self, "posts.user_id", "users.id")
    .orderBy("users.name")
    .getJoinedOptional(Post.self)

for row in rows {
    print(row.base.name)
    print(row.joined?.title ?? "Sem post")
}
```

`getJoined` retorna `[JoinedRow<Base, Joined>]`. `getJoinedOptional` retorna `[OptionalJoinedRow<Base, Joined>]` e é apropriado para `leftJoin`. Com dois joins, `getJoined(Post.self, Category.self)` retorna `JoinedRow3` (e `getJoinedOptional` a variante opcional).

Se somente a model principal for necessária, finalize a consulta com `.get()`.

Use colunas qualificadas (`users.id`, `posts.user_id`) para evitar ambiguidades.

## Migrations

Migrations implementam `AsyncMigration`:

```swift
import Fluent

struct CreatePosts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("posts")
            .id()
            .field("user_id", .uuid, .required)
            .field("title", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("posts").delete()
    }
}
```

Registre toda migration em `App/configure.swift`:

```swift
app.migrations.add(CreatePosts())
```

Execute migrations pendentes:

```bash
swift run Swiftra migrate
```

Reverta o último lote:

```bash
swift run Swiftra migrate --revert
```

O comando `make:migration` cria o arquivo, mas não o registra automaticamente em `configure.swift`.

## Autenticação

Tabelas separadas da tabela `users`:

- `user_credentials`: hash BCrypt da senha, segredo TOTP e códigos de recuperação (hashes).
- `auth_tokens`: SHA-256 do access token, usuário e expiração.
- `refresh_tokens`: SHA-256 do refresh token, com família, revogação e detecção de reuso.
- `password_reset_tokens`, `email_verification_tokens`, `mfa_challenges`: tokens de uso único com expiração.
- `roles`, `permissions` e pivôs `user_roles`, `role_permissions`, `user_permissions`.

Tokens possuem 256 bits aleatórios. O access token vive `AUTH_ACCESS_TOKEN_TTL_MINUTES` (padrão 60) e o refresh, `AUTH_REFRESH_TOKEN_TTL_DAYS` (padrão 30) — nada fixo no código. Só hashes são persistidos; o texto puro aparece uma única vez na resposta. Endpoints públicos de autenticação têm rate limiting (`RATE_LIMIT_AUTH_MAX` por `RATE_LIMIT_AUTH_DECAY_SECONDS`, por IP, com `429` + `Retry-After`).

### Endpoints

| Método | Endpoint | Protegido | Sucesso |
|---|---|---:|---:|
| `POST` | `/api/auth/register` | Não (throttle) | `201 Created` |
| `POST` | `/api/auth/login` | Não (throttle) | `200 OK` ou desafio MFA |
| `POST` | `/api/auth/refresh` | Refresh token | `200 OK` (rotaciona) |
| `POST` | `/api/auth/forgot-password` | Não (throttle) | `200 OK` (sempre genérico) |
| `POST` | `/api/auth/reset-password` | Token do email | `200 OK` |
| `POST` | `/api/auth/verify-email` | Token do email | `200 OK` |
| `POST` | `/api/auth/mfa/challenge` | Desafio + TOTP | `200 OK` |
| `GET` | `/api/auth/me` | Bearer | `200 OK` |
| `POST` | `/api/auth/logout` | Bearer | `204 No Content` |
| `POST` | `/api/auth/logout-all` | Bearer | `204 No Content` |
| `POST` | `/api/auth/email/resend-verification` | Bearer | `200 OK` |
| `POST` | `/api/auth/mfa/setup` · `enable` · `disable` | Bearer | segredo/códigos/`204` |

### Registro

```bash
curl -X POST http://127.0.0.1:8080/api/auth/register \
  -H 'content-type: application/json' \
  -d '{
    "name":"Taylor",
    "email":"taylor@example.com",
    "password":"secret123",
    "password_confirmation":"secret123"
  }'
```

Regras atuais:

- Nome não vazio.
- Email contendo `@`.
- Senha com no mínimo 8 caracteres.
- `password_confirmation` igual à senha.
- Email único, normalizado para minúsculas.

Possíveis respostas: `201`, `409` para email já registrado e `422` para entrada inválida.

Resposta de sucesso:

```json
{
  "token": "ACCESS_TOKEN",
  "token_type": "Bearer",
  "expires_at": "DATA_DE_EXPIRACAO",
  "expires_in": 3600,
  "refresh_token": "REFRESH_TOKEN",
  "refresh_expires_at": "DATA_DE_EXPIRACAO_DO_REFRESH",
  "user": { "id": "UUID", "name": "Taylor", "email": "taylor@example.com" }
}
```

Uso do refresh (o token antigo é invalidado; reutilizá-lo revoga a família inteira):

```bash
curl -X POST http://127.0.0.1:8080/api/auth/refresh \
  -H 'content-type: application/json' \
  -d '{"refresh_token":"REFRESH_TOKEN"}'
```

### Login

```bash
curl -X POST http://127.0.0.1:8080/api/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"taylor@example.com","password":"secret123"}'
```

Credenciais inválidas retornam `401 Unauthorized`.

### Usuário atual

```bash
curl http://127.0.0.1:8080/api/auth/me \
  -H 'authorization: Bearer SEU_TOKEN'
```

### Logout

```bash
curl -X POST http://127.0.0.1:8080/api/auth/logout \
  -H 'authorization: Bearer SEU_TOKEN'
```

Após o `204`, o mesmo token retorna `401` em rotas protegidas. `logout` aceita um corpo opcional `{"refresh_token": "..."}` para encerrar também a sessão longa; `logout-all` revoga todos os dispositivos. Redefinir a senha também revoga todas as sessões.

### Recuperação de senha, verificação de email e MFA

```bash
curl -X POST http://127.0.0.1:8080/api/auth/forgot-password \
  -H 'content-type: application/json' -d '{"email":"taylor@example.com"}'
# O link vai pelo mailer configurado (MAIL_MAILER=log ou smtp). Em APP_ENV=testing a resposta
# inclui reset_token, como um mail catcher local.

curl -X POST http://127.0.0.1:8080/api/auth/reset-password \
  -H 'content-type: application/json' \
  -d '{"token":"TOKEN","email":"taylor@example.com","password":"new-secret-1","password_confirmation":"new-secret-1"}'
```

O registro cria um token de verificação de email (mailer log por padrão). Com `AUTH_REQUIRE_VERIFIED_EMAIL=true`, o login exige `POST /api/auth/verify-email` concluído. O MFA é TOTP (RFC 6238, compatível com autenticadores comuns): `mfa/setup` devolve segredo + `otpauth_uri`, `mfa/enable` confirma com um código e emite 8 códigos de recuperação de uso único; no login seguinte, a resposta traz `mfa_required` + `challenge_token` para `POST /api/auth/mfa/challenge`.

### Papéis e permissões

O registro atribui o papel `AUTH_DEFAULT_ROLE` (padrão `user`); `swift run Swiftra db:seed` cria `admin` (todas) e `user` e as permissões `users.*`/`posts.*`. Na model: `user.hasRole("admin", on:)`, `user.can("users.delete", on:)`, `assignRole`, `givePermissionTo`. Em rotas: `RequireRoleMiddleware("admin")`, `RequirePermissionMiddleware("users.delete")` e `EnsureEmailVerifiedMiddleware()`.

### Helper Auth

Dentro de uma rota protegida:

```swift
let user = Auth.user()              // User?
let id = Auth.id()                  // UUID?
let authenticated = Auth.check()   // Bool
let required = try Auth.requireUser() // User ou 401
```

O contexto é local à task da requisição e é preenchido pelo `AuthMiddleware`.

## Middleware

### Middleware global

Registre em `App/configure.swift`:

```swift
app.middleware.use(MyMiddleware())
```

Middleware global atual:

- `FileMiddleware`: arquivos públicos.
- `ErrorMiddleware`: converte erros em respostas HTTP.
- `EloquentMiddleware`: disponibiliza o banco no contexto da requisição.

### Middleware de rota

`AuthMiddleware` exige um Bearer token válido e não expirado:

```swift
route.group("api") { api in
    api.middleware(AuthMiddleware()) { authenticated in
        authenticated.get("me", use: controller(AuthController.self, AuthController.me))
    }
}
```

### Middleware personalizado

```swift
import Vapor

struct ExampleMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        request.logger.info("Request recebida")
        return try await next.respond(to: request)
    }
}
```

## CLI

Execute comandos com `swift run Swiftra <comando>`.

| Comando | Finalidade |
|---|---|
| `serve` | Inicia o servidor HTTP. |
| `route:list` | Lista método e caminho das rotas. |
| `routes` | Listagem nativa de rotas do Vapor. |
| `migrate` | Executa migrations pendentes. |
| `migrate --revert` | Reverte o último lote. |
| `make:controller NomeController` | Cria um controller básico. |
| `make:model Nome` | Cria uma model `EloquentModel`. |
| `make:migration Nome` | Cria uma migration vazia. |
| `make:factory NomeFactory` | Cria uma factory de model. |
| `db:seed` | Cria papéis/permissões padrão (admin/user). |

Exemplos:

```bash
swift run Swiftra serve
swift run Swiftra serve --hostname 0.0.0.0 --port 8081
swift run Swiftra route:list
swift run Swiftra migrate
swift run Swiftra migrate --revert
swift run Swiftra make:controller PostController
swift run Swiftra make:model Category
swift run Swiftra make:migration CreateCategories
swift run Swiftra make:factory PostFactory
swift run Swiftra db:seed
```

Os geradores não sobrescrevem arquivos existentes. O controller gerado é um esqueleto básico; adicione conformidade a `Controller` e `init()` quando quiser registrá-lo pelo helper `controller(...)`. A migration gerada precisa ser registrada manualmente.

## API de exemplo

O projeto inclui um CRUD JSON de usuários **protegido**: todas as rotas exigem Bearer token e a exclusão exige o papel `admin` (usuário comum recebe `403`). A listagem é paginada (`?page=`, `?per_page=`, `?search=`).

| Método | Endpoint | Ação | Resposta principal |
|---|---|---|---:|
| `GET` | `/api/users` | Lista usuários por nome. | `200` |
| `POST` | `/api/users` | Cria usuário. | `201` |
| `GET` | `/api/users/:id` | Exibe usuário. | `200` ou `404` |
| `PUT` | `/api/users/:id` | Atualiza usuário. | `200`, `404` ou `409` |
| `DELETE` | `/api/users/:id` | Exclui usuário. | `204` ou `404` |

Criar:

```bash
# Todas as chamadas usam: -H 'authorization: Bearer [REDACTED]'
curl -X POST http://127.0.0.1:8080/api/users \
  -H 'authorization: Bearer [REDACTED]' \
  -H 'content-type: application/json' \
  -d '{"name":"Taylor","email":"taylor@example.com"}'
```

Listar:

```bash
curl 'http://127.0.0.1:8080/api/users?page=1&per_page=15' \
  -H 'authorization: Bearer [REDACTED]'
```

Exibir:

```bash
curl http://127.0.0.1:8080/api/users/UUID
```

Atualizar:

```bash
curl -X PUT http://127.0.0.1:8080/api/users/UUID \
  -H 'content-type: application/json' \
  -d '{"name":"Taylor Updated","email":"taylor@example.com"}'
```

Excluir:

```bash
curl -X DELETE http://127.0.0.1:8080/api/users/UUID
```

A página HTML `/users` demonstra controller, `view`, `compact` e SwiftBlade.

## Testes

Execute:

```bash
swift test
```

A suíte usa Swift Testing, `VaporTesting` e SQLite em memória (19 testes). Ela cobre:

- SwiftBlade: escape/raw, condicionais, loops com `loop.*`, switch, layouts/seções/stacks, includes, componentes em disco, `compact` ilimitado e vetores oficiais de SHA-1/TOTP.
- Controller retornando view com `compact` e `@forelse` iterando usuários reais.
- CRUD de `User` autenticado, paginado e com exclusão restrita a `admin`.
- Eloquent: erros tipados sem crash, operadores/key paths, paginação, eager loading, soft deletes, factories, `whereIn/pluck/whereNull` e rate limiter.
- Autenticação: registro/login/logout, rotação de refresh com detecção de reuso, reset de senha, verificação de email, MFA completo e papéis/permissões.

Integração MySQL real (migrations, auth, CRUD, joins e paginação contra MySQL 8.4):

```bash
./scripts/test-mysql.sh   # usa DB_* do ambiente; sobe docker compose se preciso
```

Sem `SWIFTRA_MYSQL_TEST=1` essa suíte é ignorada. O CI (`.github/workflows/ci.yml`) roda a suíte SQLite e um job separado contra MySQL 8.4.

Estrutura recomendada para novos testes:

```swift
@Test("Example")
func example() async throws {
    let app = try await Application.make(.testing)
    try await configure(app)
    try await app.autoMigrate()
    defer { Task { try await app.asyncShutdown() } }

    let response = try await app.testing().sendRequest(.GET, "")
    #expect(response.status == .ok)
}
```

## Produção

Antes de publicar:

1. Use MySQL ou um arquivo SQLite persistente e protegido por backup.
2. Injete credenciais por variáveis de ambiente; não envie `.env` ao repositório.
3. Execute migrations como uma etapa controlada do deploy.
4. Coloque o servidor atrás de um proxy com TLS.
5. Defina `APP_HOST` e `APP_PORT` de acordo com a infraestrutura.
6. Ajuste `RATE_LIMIT_*` e `AUTH_*_TTL_*` ao seu caso; mantenha `RATE_LIMIT_DRIVER=database` em produção com várias instâncias.
7. Adicione observabilidade, política de logs e monitoramento.
8. Planeje limpeza periódica de tokens expirados/revogados e de `rate_limit_entries` expiradas.
9. Configure email real (`MAIL_MAILER=smtp`, `MAIL_HOST`, credenciais) e `DB_TLS=required` com certificado válido.
10. Execute `./scripts/test-mysql.sh` e os testes no sistema operacional de produção.

## Solução de problemas

### `No database is available`

A consulta Eloquent foi iniciada fora de uma requisição. Use:

```swift
User.on(database).where("email", email)
```

### View não encontrada

`view("users.index", ...)` procura:

```text
Resources/Views/users/index.blade.html
```

Confirme o diretório, o nome e a extensão.

### MySQL não conecta

Verifique:

- Serviço MySQL em execução.
- `DB_CONNECTION=mysql`.
- Host e porta acessíveis.
- Banco criado.
- Usuário, senha e permissões.
- Firewall e política de rede.

Use `swift run Swiftra migrate` para provocar uma conexão e obter o erro do driver.

### Tabela não existe

Execute:

```bash
swift run Swiftra migrate
```

Confirme também se a migration foi adicionada a `app.migrations`.

### Rota não aparece

Confirme que `routes(app)` é chamado em `configure.swift` e execute:

```bash
swift run Swiftra route:list
```

### Token retorna `401`

O token pode estar ausente, malformado, expirado ou removido pelo logout. O header deve seguir exatamente:

```text
Authorization: Bearer SEU_TOKEN
```

## Limitações atuais

Nenhuma limitação funcional aberta no escopo do scaffold. Os pontos que
existiam nas primeiras versões foram corrigidos:

- **SwiftBlade completo**: layouts multinível com `@parent` encadeado, `@swift`
  com atribuições, métodos sobre valores (`user.name.uppercased()`,
  `items.count()`, `tags.join(', ')`, chamadas encadeadas) e todas as
  diretivas de loop/condição/include/componente.
- **Colunas e operadores**: além das strings (validadas com `EloquentError`,
  sem derrubar o processo), há superfície totalmente tipada — `QueryOperator`,
  `SortDirection` e overloads por key path para `where/whereIn/whereNotIn/
  whereNull/whereNotNull/whereBetween/whereColumn/orderBy`.
- **Relações polimórficas**: `morphMany`/`morphTo` com registro de tipos
  (`MorphRegistry`), exemplificadas por `Comment` sobre `User`/`Post`.
- **Rate limiting compartilhado**: driver `database` por padrão
  (`rate_limit_entries`, válido entre instâncias); `memory` segue disponível
  para processo único/testes via `RATE_LIMIT_DRIVER`.
- **Email real**: `MAIL_MAILER=smtp` usa o `SMTPMailer` (NIO + NIOSSL, com
  `none`/`starttls`/`tls` e `AUTH LOGIN`); `log` continua como padrão de
  desenvolvimento.
- **MySQL no fluxo padrão**: `make test` roda a suíte SQLite e, havendo
  MySQL acessível, a integração real; o CI executa o job MySQL 8.4 em todo
  push/PR mesmo sem servidor local.

Decisões conscientes que permanecem (não são defeitos): expressões Blade não
não são PHP: o bloco de código do template é o `@swift`, com declarações
`let`/`var` e expressões SwiftBlade, no espírito da linguagem do framework e consultas string-based são validadas em execução como no
próprio Laravel — a verificação em compilação está nas variantes tipadas.

## Validação do scaffold

Comandos usados para validar a base:

```bash
swift build
swift test
.build/debug/Swiftra route:list
```

Os testes locais validam o comportamento com SQLite em memória e, com `SWIFTRA_MYSQL_TEST=1`, também contra um MySQL real (validado localmente contra MySQL 8.4.11 e no CI).
