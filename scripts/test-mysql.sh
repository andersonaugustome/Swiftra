#!/usr/bin/env bash
# Executa a suíte de integração contra um MySQL real.
#
# Uso:
#   ./scripts/test-mysql.sh
#   DB_HOST=127.0.0.1 DB_PORT=3306 DB_USERNAME=root DB_PASSWORD= ./scripts/test-mysql.sh
#
# Sobe o MySQL via docker compose se ele estiver disponível e nenhum
# servidor responder na porta configurada.
set -euo pipefail

export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_PORT="${DB_PORT:-3306}"
export DB_DATABASE="${DB_DATABASE:-swiftra_test}"
export DB_USERNAME="${DB_USERNAME:-swiftra}"
export DB_PASSWORD="${DB_PASSWORD:-swiftra}"

case "$DB_DATABASE" in
  *test*) ;;
  *) echo "DB_DATABASE deve conter 'test' (recebido: $DB_DATABASE)" >&2; exit 1 ;;
esac

if ! (echo > "/dev/tcp/${DB_HOST}/${DB_PORT}") 2>/dev/null; then
  if command -v docker >/dev/null 2>&1; then
    echo "MySQL não responde; subindo via docker compose..."
    docker compose up -d mysql
    for _ in $(seq 1 30); do
      (echo > "/dev/tcp/${DB_HOST}/${DB_PORT}") 2>/dev/null && break
      sleep 2
    done
  else
    echo "Nenhum MySQL em ${DB_HOST}:${DB_PORT} e docker não encontrado." >&2
    exit 1
  fi
fi

if command -v mysql >/dev/null 2>&1; then
  MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" \
    -e "CREATE DATABASE IF NOT EXISTS \`${DB_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
fi

export SWIFTRA_MYSQL_TEST=1
echo "Rodando integração MySQL contra ${DB_HOST}:${DB_PORT}/${DB_DATABASE}..."
swift test --filter MySQLIntegrationTests
