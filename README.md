# Airflow CeleryExecutor — Docker Compose Setup

A production-aware Apache Airflow setup using **CeleryExecutor**, **Redis** as the message broker, and **PostgreSQL** as the metadata database. Includes Flower for real-time worker monitoring.

---

## Stack

| Service    | Image                              | Purpose                                      |
|------------|------------------------------------|----------------------------------------------|
| postgres   | postgres:14.0                      | Airflow metadata database                    |
| redis      | redis:7.2                          | Celery message broker                        |
| webserver  | apache/airflow:2.9.3-python3.9     | Airflow UI on port 8080                      |
| scheduler  | apache/airflow:2.9.3-python3.9     | Parses DAGs and schedules task instances     |
| worker     | apache/airflow:2.9.3-python3.9     | Picks up and executes tasks from Redis queue |
| flower     | apache/airflow:2.9.3-python3.9     | Celery monitoring UI on port 5555            |

---

## Project Structure

```
project/
├── docker-compose.yml        # All service definitions
├── .env                      # Credentials and secrets (never commit this)
├── .gitignore                # Ensures .env stays out of version control
├── requirements.txt          # Airflow extras and DAG dependencies
├── dags/                     # Place your DAG files here
└── script/
    └── entrypoint.sh         # Webserver bootstrap script
```

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed
- [Docker Compose](https://docs.docker.com/compose/install/) v2+ installed
- `openssl` available in your terminal (pre-installed on macOS and most Linux distros)

Verify:

```bash
docker --version
docker compose version
openssl version
```

---

## Step 1 — Generate Secrets

You need two secrets before starting. Never hardcode these or reuse them across projects.

### `AIRFLOW_SECRET_KEY` — 64-character hex string

Used internally by Airflow to sign sessions and tokens.

```bash
openssl rand -hex 32
```

Example output:

```
7f3b92ad1e6c84f0253d9a1b78e4c6d5f2a3b8e1d4c7f0a2b5e8d3c6f9a2b4e1
```

### `AIRFLOW_ADMIN_PASSWORD` — Base64 string

Used to log into the Airflow UI at `http://localhost:8080`.

```bash
openssl rand -base64 16
```

Example output:

```
Kx9mP2vLnQ7wRbYz==
```

> Run these commands yourself — do not use example values shown here or anywhere online.

---

## Step 2 — Configure `.env`

Open `.env` and replace every placeholder with your generated values:

```env
# Postgres
POSTGRES_USER=airflow
POSTGRES_PASSWORD=your_strong_password_here
POSTGRES_DB=airflow

# Airflow
AIRFLOW_SECRET_KEY=output_from_openssl_rand_hex_32
AIRFLOW_ADMIN_PASSWORD=output_from_openssl_rand_base64_16
```

**Rules:**

- `POSTGRES_PASSWORD` — pick a strong password, not `airflow` or `admin`
- `AIRFLOW_SECRET_KEY` — paste the full output from `openssl rand -hex 32`
- `AIRFLOW_ADMIN_PASSWORD` — paste the full output from `openssl rand -base64 16`

---

## Step 3 — Make the Entrypoint Executable

Docker volume mounts preserve file permissions. If `entrypoint.sh` isn't executable, the webserver container will fail immediately with a permission error.

```bash
chmod +x ./script/entrypoint.sh
```

Run this once. You don't need to repeat it unless you re-clone the repo.

---

## Step 4 — Start the Stack

```bash
docker compose up -d
```

**What `-d` does:** Runs all containers in detached mode (background). Your terminal stays free.

**What happens in order:**

1. `postgres` starts and waits until healthy (`pg_isready` passes)
2. `redis` starts and waits until healthy (`redis-cli ping` passes)
3. `webserver` starts — runs `entrypoint.sh` which installs requirements, upgrades the DB schema, creates the admin user, then starts the Airflow webserver
4. `scheduler` and `worker` wait for the webserver to pass its healthcheck, then start
5. `flower` starts once Redis is healthy

The full startup takes roughly **2–3 minutes** on first run due to `pip install`.

---

## Step 5 — Verify Everything is Running

Check container status:

```bash
docker compose ps
```

All services should show `healthy` or `running`. If any show `exited`, check logs immediately (see Troubleshooting below).

---

## Step 6 — Access the UIs

| UI          | URL                      | Credentials                     |
|-------------|--------------------------|----------------------------------|
| Airflow     | <http://localhost:8080>    | `admin` / your AIRFLOW_ADMIN_PASSWORD |
| Flower      | <http://localhost:5555>    | No login by default              |

---

## Scaling Workers

CeleryExecutor's main advantage is horizontal scaling. Add more workers without touching any config:

```bash
docker compose up -d --scale worker=3
```

This spins up 3 worker containers. All of them pull tasks from the same Redis queue. Scale back down the same way:

```bash
docker compose up -d --scale worker=1
```

---

## Common Commands

### View logs for a specific service

```bash
docker compose logs -f webserver
docker compose logs -f scheduler
docker compose logs -f worker
```

### Restart a single service

```bash
docker compose restart scheduler
```

### Stop everything (keeps data)

```bash
docker compose down
```

### Stop everything and wipe all data (fresh start)

```bash
docker compose down -v
```

> `-v` removes named volumes. This deletes your Postgres database and all DAG run history. Only use this when you want a clean slate.

### Run a one-off Airflow CLI command

```bash
docker compose exec webserver airflow dags list
docker compose exec webserver airflow users list
```

---

## Adding DAG Dependencies

Put any Python packages your DAGs need in `requirements.txt` below the existing line:

```text
apache-airflow[celery,redis]==2.9.3

# Your dependencies
pandas==2.0.3
requests==2.31.0
```

Then restart the affected containers to reinstall:

```bash
docker compose restart webserver scheduler worker
```

---

## Troubleshooting

### Webserver exits immediately

```bash
docker compose logs webserver
```

Usually one of: `entrypoint.sh` not executable, bad `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN`, or a failed `pip install`.

### Tasks stuck in "queued" state

Means the worker isn't picking up from Redis. Check:

```bash
docker compose logs worker
docker compose ps redis
```

Open Flower at `http://localhost:5555` — if no workers appear, the worker container failed to connect to Redis.

### `could not connect to server` on Postgres

Postgres isn't ready yet or credentials in `.env` don't match. Run:

```bash
docker compose logs postgres
```

### Admin user already exists error on restart

This is handled — `entrypoint.sh` checks before creating. If you still see it, the grep check failed. Run:

```bash
docker compose exec webserver airflow users list
```

---

## Security Checklist Before Exposing to a Network

- [ ] Change all `.env` values from defaults
- [ ] Add basic auth to Flower: `--basic-auth=user:strongpassword` in `docker-compose.yml`
- [ ] Put Airflow behind a reverse proxy (nginx/traefik) with HTTPS
- [ ] Restrict port access via firewall — `8080` and `5555` should not be public
- [ ] Rotate `AIRFLOW_SECRET_KEY` if it was ever committed or shared
