SHELL := /bin/bash
.PHONY: build test test-mysql serve migrate seed routes

build:
	swift build

## Suíte padrão (SQLite) + integração MySQL quando houver servidor.
## Sem MySQL acessível, a suíte de integração é ignorada com aviso.
test:
	swift test
	@if (echo > /dev/tcp/$${DB_HOST:-127.0.0.1}/$${DB_PORT:-3306}) 2>/dev/null; then \
		echo "MySQL detectado: rodando integração..."; \
		$(MAKE) test-mysql; \
	else \
		echo "MySQL não detectado em $${DB_HOST:-127.0.0.1}:$${DB_PORT:-3306}; integração ignorada (rode 'make test-mysql' para forçar)."; \
	fi

test-mysql:
	./scripts/test-mysql.sh

serve:
	swift run Swiftra serve

migrate:
	swift run Swiftra migrate

seed:
	swift run Swiftra db:seed

routes:
	swift run Swiftra route:list
