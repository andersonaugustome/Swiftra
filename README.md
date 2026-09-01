# Swiftra

Swiftra é um scaffold de framework server-side escrito em Swift 6, construído sobre Vapor e Fluent. O projeto oferece uma organização familiar para aplicações web, rotas concisas, controllers assíncronos, views HTML, uma camada de consultas fluente, migrations, autenticação Bearer e CLI.

> Estado atual: MVP funcional. A base compila e possui testes para views, CRUD, joins e autenticação. Consulte [Limitações atuais](#limitações-atuais) antes de adotá-la em produção.

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
- SwiftBlade com interpolação escapada `{{ variable }}` e nomes de view com pontos.
- Fluent com uma API simplificada: `where`, `whereIn`, `orderBy`, `limit`, `find`, `first`, `firstOrFail`, `get`, `count`, `exists`, `save` e `delete`.
- `join` e `leftJoin` com retorno das models participantes.
- SQLite para desenvolvimento e testes.
- MySQL por configuração de ambiente.
- Migrations assíncronas.
- Autenticação nativa com BCrypt, Bearer tokens, expiração e logout.
- CLI com servidor, migrations, listagem de rotas e geradores.
- CRUD JSON de `User` e relacionamento de exemplo com `Post`.

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

Execute as migrations e inicie o servidor:

```bash
swift run Swiftra migrate
swift run Swiftra serve
```

Models, consultas, joins, autenticação e migrations usam Fluent. Os controllers não precisam ser modificados ao trocar SQLite por MySQL.

Durante os testes, a aplicação força SQLite em memória, independentemente do `.env`.

## Estrutura do projeto

```text
.
├── App/
│   ├── Auth/                  # Contexto e middleware de autenticação
│   ├── Console/               # Comandos da CLI
│   ├── Database/              # Camada Eloquent e contexto de banco
│   ├── Http/Controllers/      # Controllers HTTP
│   ├── Models/                # Models Fluent
│   ├── Routing/               # SwiftraRouter e adaptação de controllers
│   ├── Support/               # .env, view e compact
│   ├── Views/                 # Engine SwiftBlade
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

`compact` possui overloads para um, dois ou três pares chave/valor:

```swift
compact("user", user)
compact("title", title, "user", user)
compact("title", title, "user", user, "active", true)
```

Valores interpolados são escapados para HTML (`&`, `<`, `>`, aspas simples e duplas). Uma chave ausente resulta em string vazia.

## Models e Eloquent

Uma model implementa `EloquentModel` e pode também implementar `Content` para entrada/saída HTTP:

```swift
import Fluent
import Vapor

final class Post: EloquentModel, Content, @unchecked Sendable {
    static let schema = "posts"

    @ID(key: .id) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "title") var title: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userId: UUID, title: String) {
        self.id = id
        self.userId = userId
        self.title = title
    }
}
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

Operadores desconhecidos causam falha de precondição. As direções de ordenação aceitas são `asc`, `ascending`, `desc` e `descending`.

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

`getJoined` retorna `[JoinedRow<Base, Joined>]`. `getJoinedOptional` retorna `[OptionalJoinedRow<Base, Joined>]` e é apropriado para `leftJoin`.

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

A autenticação usa duas tabelas separadas da tabela `users`:

- `user_credentials`: hash BCrypt da senha por usuário.
- `auth_tokens`: SHA-256 do token, usuário, expiração e criação.

O token em texto puro é retornado apenas ao registrar ou autenticar. Tokens possuem 256 bits aleatórios, expiram em 30 dias e são removidos no logout.

### Endpoints

| Método | Endpoint | Protegido | Sucesso |
|---|---|---:|---:|
| `POST` | `/api/auth/register` | Não | `201 Created` |
| `POST` | `/api/auth/login` | Não | `200 OK` |
| `GET` | `/api/auth/me` | Bearer | `200 OK` |
| `POST` | `/api/auth/logout` | Bearer | `204 No Content` |

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
  "token": "TOKEN_EM_TEXTO_PURO",
  "tokenType": "Bearer",
  "expiresAt": "DATA_DE_EXPIRACAO",
  "user": {
    "id": "UUID",
    "name": "Taylor",
    "email": "taylor@example.com",
    "createdAt": "DATA_DE_CRIACAO",
    "updatedAt": null
  }
}
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

Após o `204`, o mesmo token retorna `401` em rotas protegidas. Outros tokens emitidos para o usuário continuam válidos.

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
```

Os geradores não sobrescrevem arquivos existentes. O controller gerado é um esqueleto básico; adicione conformidade a `Controller` e `init()` quando quiser registrá-lo pelo helper `controller(...)`. A migration gerada precisa ser registrada manualmente.

## API de exemplo

O projeto inclui um CRUD JSON de usuários. Essas rotas são públicas no scaffold atual.

| Método | Endpoint | Ação | Resposta principal |
|---|---|---|---:|
| `GET` | `/api/users` | Lista usuários por nome. | `200` |
| `POST` | `/api/users` | Cria usuário. | `201` |
| `GET` | `/api/users/:id` | Exibe usuário. | `200` ou `404` |
| `PUT` | `/api/users/:id` | Atualiza usuário. | `200`, `404` ou `409` |
| `DELETE` | `/api/users/:id` | Exclui usuário. | `204` ou `404` |

Criar:

```bash
curl -X POST http://127.0.0.1:8080/api/users \
  -H 'content-type: application/json' \
  -d '{"name":"Taylor","email":"taylor@example.com"}'
```

Listar:

```bash
curl http://127.0.0.1:8080/api/users
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

A suíte usa Swift Testing, `VaporTesting` e SQLite em memória. Ela cobre:

- Renderização da página inicial.
- Controller retornando view com `compact`.
- CRUD completo de `User`.
- `inner join` e `left join` entre `User` e `Post`.
- Registro, login, senha inválida, rota protegida, logout e token revogado.

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
6. Adicione rate limiting aos endpoints de registro e login.
7. Adicione observabilidade, política de logs e monitoramento.
8. Planeje limpeza periódica de tokens expirados.
9. Revise quais rotas devem usar `AuthMiddleware`; o CRUD de exemplo é público.
10. Execute testes contra o banco e o sistema operacional usados em produção.

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

- SwiftBlade suporta apenas interpolação `{{ chave }}`; ainda não possui layouts, diretivas, loops, condicionais, includes ou componentes.
- Coleções interpoladas em SwiftBlade são convertidas por descrição textual; ainda não existe uma diretiva de iteração no template.
- `compact` aceita no máximo três pares chave/valor.
- A API Eloquent cobre operações comuns, mas não substitui toda a API do Fluent.
- Nomes de colunas e operadores em consultas string-based são verificados em execução, não em compilação.
- Operador ou direção inválidos encerram a execução por precondição.
- `getJoined` e `getJoinedOptional` trabalham com uma model relacionada por leitura.
- Não há paginação, eager loading simplificado, relações declarativas, soft deletes ou factories na camada Eloquent atual.
- Não há refresh tokens, recuperação de senha, confirmação de email, autenticação multifator, papéis ou permissões.
- O prazo do token está fixado em 30 dias no código.
- Não há rate limiting nos endpoints de autenticação.
- O CRUD `/api/users` é público no scaffold de exemplo.
- O suporte MySQL compila com o driver oficial, mas esta suíte não executa contra um servidor MySQL real.

## Validação do scaffold

Comandos usados para validar a base:

```bash
swift build
swift test
.build/debug/Swiftra route:list
```

Os testes locais validam o comportamento com SQLite em memória. Eles não comprovam conectividade, migrations ou comportamento de um servidor MySQL externo.
