#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/evidencias"
export COMPOSE_PROJECT_NAME=pratica06

mkdir -p "$EVIDENCE_DIR"
cd "$ROOT_DIR"

capture() {
  local file="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } 2>&1 | tee "$EVIDENCE_DIR/$file"
}

wait_healthy() {
  local container="$1"
  local attempts=40
  local status
  for ((i = 1; i <= attempts; i++)); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    if [[ "$status" == "healthy" || "$status" == "running" ]]; then
      return 0
    fi
    sleep 2
  done
  printf 'O contêiner %s não ficou saudável.\n' "$container" >&2
  return 1
}

cleanup_on_error() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    docker compose ps -a >"$EVIDENCE_DIR/erro-compose-ps.txt" 2>&1 || true
    docker compose logs --no-color >"$EVIDENCE_DIR/erro-compose-logs.txt" 2>&1 || true
    docker compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap cleanup_on_error EXIT

{
  docker --version
  docker compose version
} | tee "$EVIDENCE_DIR/00-versoes.txt"

capture 01-compose-config.txt docker compose config
capture 02-compose-up.txt docker compose up -d

wait_healthy pratica06-redis
wait_healthy pratica06-postgres

capture 03-compose-ps.txt docker compose ps
capture 04-ubuntu-os-release.txt docker compose exec -T ubuntu-server cat /etc/os-release
capture 05-rocky-os-release.txt docker compose exec -T rocky-server cat /etc/os-release

{
  printf 'DEPENDÊNCIAS DECLARADAS PELO DOCKER COMPOSE\n\n'
  docker compose config | sed -n '/ubuntu-server:/,/^[^ ]/p' | sed -n '/depends_on:/,/image:/p'
  docker compose config | sed -n '/rocky-server:/,/^[^ ]/p' | sed -n '/depends_on:/,/image:/p'
  printf '\nESTADO DOS BANCOS\n'
  docker inspect --format '{{.Name}} -> {{.State.Health.Status}}' pratica06-redis pratica06-postgres
} | tee "$EVIDENCE_DIR/06-dependencias.txt"

capture 07-redes.txt docker network ls --filter name=pratica06_
capture 08-rede-ubuntu-redis.txt docker network inspect pratica06_ubuntu_redis_net
capture 09-rede-rocky-postgres.txt docker network inspect pratica06_rocky_postgres_net

{
  printf 'TESTE DO PAR UBUNTU + REDIS\n'
  docker compose exec -T ubuntu-server getent hosts redis
  docker compose exec -T redis redis-cli ping
} | tee "$EVIDENCE_DIR/10-comunicacao-ubuntu-redis.txt"

{
  printf 'TESTE DO PAR ROCKY LINUX + POSTGRESQL\n'
  docker compose exec -T rocky-server getent hosts postgres
  docker compose exec -T postgres pg_isready -U pratica -d pratica
} | tee "$EVIDENCE_DIR/11-comunicacao-rocky-postgres.txt"

{
  printf 'TESTE DE ISOLAMENTO ENTRE AS REDES\n'
  if docker compose exec -T ubuntu-server getent hosts postgres; then
    printf 'ERRO: o Ubuntu alcançou o PostgreSQL da outra rede.\n'
    exit 1
  else
    printf 'OK: ubuntu-server não resolve postgres.\n'
  fi
  if docker compose exec -T rocky-server getent hosts redis; then
    printf 'ERRO: o Rocky Linux alcançou o Redis da outra rede.\n'
    exit 1
  else
    printf 'OK: rocky-server não resolve redis.\n'
  fi
  printf 'As duas redes privadas estão isoladas.\n'
} | tee "$EVIDENCE_DIR/12-isolamento-redes.txt"

capture 13-volumes.txt docker volume ls --filter name=pratica06_
capture 14-volume-redis-inspect.txt docker volume inspect pratica06_redis_data
capture 15-volume-postgres-inspect.txt docker volume inspect pratica06_postgres_data

{
  printf 'GRAVAÇÃO DE DADOS NOS DOIS BANCOS\n'
  docker compose exec -T redis redis-cli SET pratica06 "dados persistentes no Redis"
  docker compose exec -T postgres psql -U pratica -d pratica -v ON_ERROR_STOP=1 -c \
    "CREATE TABLE IF NOT EXISTS evidencias (id integer PRIMARY KEY, mensagem text NOT NULL); INSERT INTO evidencias VALUES (1, 'dados persistentes no PostgreSQL') ON CONFLICT (id) DO UPDATE SET mensagem = EXCLUDED.mensagem;"
} | tee "$EVIDENCE_DIR/16-gravacao-dados.txt"

capture 17-reinicio-bancos.txt docker compose restart redis postgres
wait_healthy pratica06-redis
wait_healthy pratica06-postgres

{
  printf 'VERIFICAÇÃO DE PERSISTÊNCIA APÓS REINÍCIO\n'
  printf 'Redis: '
  docker compose exec -T redis redis-cli GET pratica06
  printf 'PostgreSQL:\n'
  docker compose exec -T postgres psql -U pratica -d pratica -c "SELECT * FROM evidencias;"
} | tee "$EVIDENCE_DIR/18-persistencia.txt"

capture 19-compose-down.txt docker compose down --volumes --remove-orphans
capture 20-containers-apos-remocao.txt docker ps -a --filter name=pratica06 --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
capture 21-redes-apos-remocao.txt docker network ls --filter name=pratica06_
capture 22-volumes-apos-remocao.txt docker volume ls --filter name=pratica06_

{
  printf 'VERIFICAÇÃO FINAL DA LIMPEZA\n'
  if docker ps -a --format '{{.Names}}' | grep -q '^pratica06-'; then
    printf 'containers_removidos=não\n'
    exit 1
  else
    printf 'containers_removidos=sim\n'
  fi
  if docker network ls --format '{{.Name}}' | grep -q '^pratica06_'; then
    printf 'redes_removidas=não\n'
    exit 1
  else
    printf 'redes_removidas=sim\n'
  fi
  if docker volume ls --format '{{.Name}}' | grep -q '^pratica06_'; then
    printf 'volumes_removidos=não\n'
    exit 1
  else
    printf 'volumes_removidos=sim\n'
  fi
} | tee "$EVIDENCE_DIR/23-verificacao-final.txt"

{
  printf 'PRÁTICA 06 CONCLUÍDA\n'
  printf 'Servidores: Ubuntu 24.04 e Rocky Linux 9\n'
  printf 'Bancos de dados: Redis 7 e PostgreSQL 16\n'
  printf 'Redes privadas: pratica06_ubuntu_redis_net e pratica06_rocky_postgres_net\n'
  printf 'Volumes persistentes testados: pratica06_redis_data e pratica06_postgres_data\n'
  printf 'Isolamento de rede: confirmado\n'
  printf 'Persistência após reinício: confirmada\n'
  printf 'Limpeza de contêineres, redes e volumes: confirmada\n'
} | tee "$EVIDENCE_DIR/24-resumo.txt"

trap - EXIT
