# DiackPain — Production Infrastructure

Deployment, CI/CD, and operations for **DiackPain**, a Django 5.0 bakery
management application, running in production at **https://diackpain.shop**.

The application code was built by [ASLIH313](https://github.com/ASLIH313).
This repository documents the infrastructure, deployment pipeline, and
operational tooling I designed and manage around it.

## Architecture

GitHub push → GitHub Actions (build + test) → EC2 (Ubuntu 24.04)
│
Docker Compose stack:
┌─────────────────────────┐
│ Nginx (reverse proxy, │
│ HTTP→HTTPS, Let's │
│ Encrypt/Certbot) │
├─────────────────────────┤
│ Gunicorn (Django app) │
├─────────────────────────┤
│ PostgreSQL │
└─────────────────────────┘
│
Nightly: pg_dump → gzip → S3 (diackpain-backups-2026)
Daily: Certbot renew via cron


- **Compute:** AWS EC2 t2.micro, Ubuntu 24.04, static Elastic IP
- **Containerization:** Docker Compose — Nginx, Gunicorn/Django, PostgreSQL
- **CI/CD:** GitHub Actions — build, test, and deploy on push
- **TLS:** Let's Encrypt via Certbot, auto-renewed nightly via cron, certs stored in a named Docker volume
- **Backups:** Nightly `pg_dump` → gzip → S3, 7-day local retention, credentials via IAM instance role (no static keys)

## Why this exists

The app was already built — the job here was making it production-ready:
containerizing it, standing up HTTPS, wiring a CI/CD pipeline, and building
backup/recovery processes so it could run unattended and survive real
operational incidents (see `RUNBOOK.md` for one of those incidents in detail).

## Tech Stack

**CI/CD:** GitHub Actions
**Containers:** Docker, Docker Compose
**Web/Proxy:** Nginx, Gunicorn
**Database:** PostgreSQL
**Cloud:** AWS EC2, S3, IAM
**TLS:** Let's Encrypt / Certbot
**Automation:** Bash, cron

## Key Engineering Decisions

- **Nginx as a reverse proxy in its own container**, rather than installed
  on the host — keeps the entire stack portable and reproducible via
  `docker-compose.yml` instead of relying on host-level package state.
- **`SECURE_PROXY_SSL_HEADER` configuration** — Django doesn't know it's
  behind a TLS-terminating proxy by default, which breaks CSRF validation
  and cookie security. Set explicitly so Django trusts the `X-Forwarded-Proto`
  header from Nginx.
- **Certbot certs in a named Docker volume** rather than a bind mount —
  survives container recreation without needing to re-issue certificates.
- **Backups via IAM instance role, not static access keys** — the backup
  script (`scripts/backup.sh`) never touches a hardcoded credential; AWS
  CLI picks up the role automatically.
- **Env-var-driven secrets in `docker-compose.yml`** — `DB_PASSWORD`,
  `SECRET_KEY`, etc. are injected at runtime, never committed.

## Challenges & Fixes

- **Migration drift after a squashed migration set was applied to
  production out of band** — required a full recovery process to bring
  Django's migration state back in sync with the live schema without data
  loss. Full step-by-step recovery documented in [`RUNBOOK.md`](./RUNBOOK.md).
- **CSRF failures behind the reverse proxy** — traced to missing
  `SECURE_PROXY_SSL_HEADER` and cookie-security settings; fixed by
  explicitly configuring Django to trust the proxy's forwarded headers.
- **HTTPS cutover** — set up Let's Encrypt via Certbot with named Docker
  volumes so certs persist across container rebuilds, plus an Nginx
  config for HTTP→HTTPS redirect and TLS termination.

## Repository Structure

docker/ → Dockerfile, docker-compose.yml
nginx/ → reverse proxy + TLS config
scripts/ → backup.sh, crontab reference
.github/ → CI/CD workflow (GitHub Actions)
docs/ → RUNBOOK.md and additional operational docs


## How to Run It

1. Clone this repo alongside the application code
2. Copy `.env.example` → `.env` and populate `DB_PASSWORD`, `SECRET_KEY`, `DB_USER`, `DB_NAME`
3. `docker compose -f docker/docker-compose.yml up -d --build`
4. Point Nginx at your domain in `nginx/diackpain.conf` and run Certbot for TLS

## Live Site

**https://diackpain.shop**
