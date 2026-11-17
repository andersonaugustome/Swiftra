@testable import App
import Foundation
import Testing

@Suite("SwiftBlade")
struct SwiftBladeTests {
    private let renderer = SwiftBladeRenderer(rootDirectory: "/tmp/swiftra-views/")

    @Test("Escapes echo and renders raw echo")
    func escaping() throws {
        #expect(try renderer.renderString("<p>{{ name }}</p>", context: ["name": "<b>Ada</b>"]) == "<p>&lt;b&gt;Ada&lt;/b&gt;</p>")
        #expect(try renderer.renderString("<p>{!! name !!}</p>", context: ["name": "<b>Ada</b>"]) == "<p><b>Ada</b></p>")
        #expect(try renderer.renderString("{{-- segredo --}}ok", context: [:]) == "ok")
    }

    @Test("Conditions, ternary, coalesce and functions")
    func conditions() throws {
        let template = "@if(age >= 18)major@elseif(age >= 12)teen@else minor@endif"
        #expect(try renderer.renderString(template, context: ["age": 20]) == "major")
        #expect(try renderer.renderString(template, context: ["age": 15]) == "teen")
        #expect(try renderer.renderString(template, context: ["age": 5]).trimmingCharacters(in: .whitespaces) == "minor")
        #expect(try renderer.renderString("{{ nickname ?? name }}", context: ["name": "Taylor"]) == "Taylor")
        #expect(try renderer.renderString("{{ age >= 18 ? 'yes' : 'no' }}", context: ["age": 3]) == "no")
        #expect(try renderer.renderString("{{ upper(name) }}:{{ count(items) }}", context: ["name": "ada", "items": [1, 2, 3]]) == "ADA:3")
        #expect(try renderer.renderString("@unless(hidden)shown@endunless", context: ["hidden": false]) == "shown")
        #expect(try renderer.renderString("@isset(name)yes@else no@endisset", context: [:]).contains("no"))
    }

    @Test("Foreach with loop metadata, forelse and switch")
    func loops() throws {
        let users: [[String: Any]] = [["name": "Ada"], ["name": "Grace"]]
        let rendered = try renderer.renderString(
            "@foreach(users as user){{ loop.iteration }}:{{ user.name }}@if(!loop.last),@endif@endforeach",
            context: ["users": users]
        )
        #expect(rendered == "1:Ada,2:Grace")

        let swiftStyle = try renderer.renderString(
            "@foreach(user in users){{ user.name }};@endforeach",
            context: ["users": users]
        )
        #expect(swiftStyle == "Ada;Grace;")

        let empty = try renderer.renderString(
            "@forelse(user in users){{ user.name }}@empty<i>none</i>@endforelse",
            context: ["users": [Any]()]
        )
        #expect(empty == "<i>none</i>")

        let switchRendered = try renderer.renderString(
            "@switch(status)@case('active')on@break@default off@endswitch",
            context: ["status": "active"]
        )
        #expect(switchRendered == "on")
    }

    @Test("Layouts, sections, yields, stacks and components from disk")
    func layouts() throws {
        let root = URL(fileURLWithPath: "/tmp/swiftra-views-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("layouts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("components"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("partials"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "<html><title>@yield('title', 'Default')</title><body>@yield('content')@stack('scripts')</body></html>"
            .write(to: root.appendingPathComponent("layouts/main.blade.html"), atomically: true, encoding: .utf8)
        try "<strong>{{ label }}: {!! slot !!}</strong>"
            .write(to: root.appendingPathComponent("components/badge.blade.html"), atomically: true, encoding: .utf8)
        try "<footer>partial {{ name }}</footer>"
            .write(to: root.appendingPathComponent("partials/foot.blade.html"), atomically: true, encoding: .utf8)

        let diskRenderer = SwiftBladeRenderer(rootDirectory: root.path + "/")
        let page = """
        @extends('layouts.main')
        @section('title')Hello {{ name }}@endsection
        @section('content')
        <x-badge label="Hi">body {{ name }}</x-badge>
        @component('badge', ['label' => 'Again'])second@endcomponent
        @include('partials.foot')
        @push('scripts')<script src="app.js"></script>@endpush
        @endsection
        """
        let rendered = try diskRenderer.renderString(page, context: ["name": "Ada"])
        #expect(rendered.contains("<title>Hello Ada</title>"))
        #expect(rendered.contains("<strong>Hi: body Ada</strong>"))
        #expect(rendered.contains("<strong>Again: second</strong>"))
        #expect(rendered.contains("<footer>partial Ada</footer>"))
        #expect(rendered.contains("<script src=\"app.js\"></script>"))
    }

    @Test("Method calls on values and chained calls")
    func methodCalls() throws {
        #expect(try renderer.renderString("{{ user.name.uppercased() }}", context: ["user": ["name": "ada"]]) == "ADA")
        #expect(try renderer.renderString("{{ items.count() }}", context: ["items": [1, 2]]) == "2")
        #expect(try renderer.renderString("{{ ' swiftra '.trim().upper() }}", context: [:]) == "SWIFTRA")
        #expect(try renderer.renderString("{{ name.contains('vel') ? 'yes' : 'no' }}", context: ["name": "Laravel"]) == "yes")
        #expect(try renderer.renderString("{{ tags.join('-') }}", context: ["tags": ["a", "b"]]) == "a-b")
        #expect(try renderer.renderString("@if(items.isEmpty())empty@endif", context: ["items": [Any]()]) == "empty")
    }

    @Test("@swift declarations and multi-level @parent")
    func phpAndParent() throws {
        let block = """
        @swift
          let total = count(items)
          var label = 'total'
          label = label.uppercased()
        @endswift
        {{ label }}:{{ total }}
        """
        let rendered = try renderer.renderString(block, context: ["items": [1, 2, 3]])
        #expect(rendered.contains("TOTAL:3"))

        let inline = try renderer.renderString(
            "@swift(let doubled = count(items) * 2){{ doubled }}",
            context: ["items": [1, 2, 3]]
        )
        #expect(inline == "6")

        let root = URL(fileURLWithPath: "/tmp/swiftra-views-parent-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("layouts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "<html><body>@section('content')BASE|@show</body></html>"
            .write(to: root.appendingPathComponent("layouts/base.blade.html"), atomically: true, encoding: .utf8)
        try "@extends('layouts.base')@section('content')MIDDLE(@parent)@endsection"
            .write(to: root.appendingPathComponent("layouts/mid.blade.html"), atomically: true, encoding: .utf8)

        let diskRenderer = SwiftBladeRenderer(rootDirectory: root.path + "/")
        let page = "@extends('layouts.mid')@section('content')PAGE(@parent)@endsection"
        let output = try diskRenderer.renderString(page, context: [:])
        #expect(output == "<html><body>PAGE(MIDDLE(BASE|))</body></html>")
    }

    @Test("Loop shortcuts work without the loop. prefix")
    func loopShortcuts() throws {
        let users: [[String: Any]] = [["name": "Ada"], ["name": "Grace"], ["name": "Linus"]]
        // Forma prática: sem `loop.` na frente.
        let rendered = try renderer.renderString(
            "@foreach(users as user){{ iteration }}. {{ user.name }}@if(!last), @endif@endforeach",
            context: ["users": users]
        )
        #expect(rendered == "1. Ada, 2. Grace, 3. Linus")

        let details = try renderer.renderString(
            "@foreach(users as user)[{{ index }}/{{ count }}:{{ first ? 'F' : '-' }}{{ last ? 'L' : '-' }}:{{ remaining }}]@endforeach",
            context: ["users": users]
        )
        #expect(details == "[0/3:F-:2][1/3:--:1][2/3:-L:0]")

        // O prefixo `loop.` continua funcionando (compatibilidade).
        let legacy = try renderer.renderString(
            "@foreach(users as user){{ loop.iteration }}@endforeach",
            context: ["users": users]
        )
        #expect(legacy == "123")

        // Exemplo do pedido: sem numeração nenhuma também funciona.
        let plain = try renderer.renderString(
            "@foreach(users as user){{ user.name }};@endforeach",
            context: ["users": users]
        )
        #expect(plain == "Ada;Grace;Linus;")
    }

    @Test("String interpolation and typed @swift declarations")
    func interpolation() throws {
        #expect(try renderer.renderString(
            "{{ \"Olá \\(name), \\(count(items)) itens\" }}",
            context: ["name": "Ada", "items": [1, 2, 3]]
        ) == "Olá Ada, 3 itens")
        // Aspas simples não interpolam, como em Swift.
        #expect(try renderer.renderString("{{ 'Olá \\(name)' }}", context: ["name": "Ada"]) == "Olá \\(name)")
        let typed = try renderer.renderString(
            "@swift(let total: Int = count(items)){{ total }}",
            context: ["items": [1, 2]]
        )
        #expect(typed == "2")
    }

    @Test("Template cache parses once and invalidates on change")
    func templateCache() throws {
        let root = URL(fileURLWithPath: "/tmp/swiftra-cache-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cached.blade.html")
        try "v1 {{ name }}".write(to: file, atomically: true, encoding: .utf8)

        let diskRenderer = SwiftBladeRenderer(rootDirectory: root.path + "/")
        #expect(try diskRenderer.render(view: "cached", context: ["name": "Ada"]) == "v1 Ada")
        #expect(try diskRenderer.render(view: "cached", context: ["name": "Grace"]) == "v1 Grace")

        // Nova mtime + conteúdo: o cache é invalidado.
        try "v2 {{ name }}".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        #expect(try diskRenderer.render(view: "cached", context: ["name": "Ada"]) == "v2 Ada")
    }

    @Test("compact accepts unlimited pairs")
    func compactUnlimited() throws {
        let data = compact(
            ("a", 1), ("b", "two"), ("c", true), ("d", [1, 2]),
            ("e", 5), ("f", "six"), ("g", 7), ("h", "eight")
        )
        let encoded = try JSONEncoder().encode(data)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object.count == 8)
        #expect(object["h"] as? String == "eight")
    }

    @Test("TOTP matches RFC 4226/6238 and SHA1 vector")
    func totp() {
        // SHA-1("abc") — FIPS 180-1.
        #expect(SHA1.hash(Array("abc".utf8)).map { String(format: "%02x", $0) }.joined()
            == "a9993e364706816aba3e25717850c26c9cd0d89d")
        // Segredo RFC: ASCII "12345678901234567890".
        let secret = Base32.encode(Array("12345678901234567890".utf8))
        let at59 = TOTP.code(secret: secret, at: Date(timeIntervalSince1970: 59))
        #expect(at59 == "287082")
        #expect(TOTP.verify("287082", secret: secret, at: Date(timeIntervalSince1970: 59)))
        #expect(!TOTP.verify("000000", secret: secret, at: Date(timeIntervalSince1970: 59)))
    }
}
