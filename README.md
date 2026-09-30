# Prática 06 - Utilizando o Docker Compose

Este repositório implementa uma infraestrutura com quatro contêineres, duas redes privadas isoladas, dependências condicionadas à saúde dos bancos de dados e dois volumes persistentes.

## Arquitetura

- `ubuntu-server`: servidor baseado em Ubuntu 24.04, conectado somente à rede do Redis.
- `redis`: banco Redis 7 com persistência AOF e volume próprio.
- `rocky-server`: servidor baseado em Rocky Linux 9, conectado somente à rede do PostgreSQL.
- `postgres`: banco PostgreSQL 16 com volume próprio.
- `pratica06_ubuntu_redis_net`: rede privada do primeiro par.
- `pratica06_rocky_postgres_net`: rede privada do segundo par.

Os servidores usam `depends_on` com `condition: service_healthy`, de modo que cada servidor só é iniciado depois que seu banco de dados está saudável.

## Execução completa

```bash
chmod +x scripts/run-all.sh
bash scripts/run-all.sh
```

O script cria a infraestrutura, demonstra os sistemas operacionais, verifica as dependências, testa a comunicação dos pares, comprova o isolamento das redes, grava dados, reinicia os bancos, confirma a persistência e remove todos os recursos.

## Comandos principais

```bash
docker compose config
docker compose up -d
docker compose ps
docker network ls --filter name=pratica06_
docker volume ls --filter name=pratica06_
docker compose down --volumes --remove-orphans
```

## Evidências

O workflow do GitHub Actions publica o artefato `evidencias-pratica-06`, contendo os resultados textuais de todas as etapas.

Documentação oficial: https://docs.docker.com/compose/
