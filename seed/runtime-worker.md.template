---
name: <kebab-case-runtime-name>
kind: worker
language: <python | javascript | typescript | go | rust | ruby | other>
framework: <celery | sidekiq | bull | rq | dramatiq | cron | other>

commands:
  install: "<install deps>"
  dev: "<run worker locally — e.g. celery -A app worker --loglevel=info>"
  test: "<test command>"
  lint: "<lint command>"

# Workers typically don't expose ports — they consume from queues / cron
# triggers / file watchers.

queue:
  name: "<queue name or topic — e.g. tasks, jobs, default>"
  broker: "<redis | rabbitmq | sqs | postgres-lf | cron | filewatcher>"
  broker_url_env: "REDIS_URL"   # env var holding the broker connection string

env:
  template: ".env-template"
  file: ".env"
  environments:                       # keys = .claude/environments.json
    local: ".env"
    prod: ".env.production"
  required: []          # e.g. [REDIS_URL, DATABASE_URL]
  optional: {}

depends_on: []          # the broker + anything the worker calls
  # - { name: redis,    check: "redis-cli ping" }
  # - { name: postgres, check: "pg_isready -h localhost" }

process:
  type: long-running
  concurrency: 1        # how many worker processes/threads

tags: []
---

# <Name> — local worker runtime

> Background worker. Long-running but consumes from a queue / cron /
> watcher rather than serving a port.

## What this is

<One paragraph: what jobs this worker handles, who enqueues them,
typical job duration. E.g. "Processes image-upload jobs from the
RTDB queue. Resizes, compresses, writes to GCS. Typical job: 2-5s.">

## How to run

```sh
<install command>
<dev command>
```

The worker will start consuming from `<queue name>`.

## First-time setup

1. Install deps: `<install command>`
2. Start the broker (see `depends_on`)
3. Set `<broker_url_env>` in `.env`
4. Run the worker command above

## Triggering jobs locally

```sh
# Enqueue a test job
<command to enqueue — e.g. python -c "from app.jobs import process_image; process_image.delay('test.jpg')">
```

## Observing job state

- Logs: stdout of the worker process
- Queue depth: `<command — e.g. redis-cli LLEN tasks>`
- Failed jobs: `<command or admin URL>`

## Gotchas

- ...

## References

- <link to queue framework docs>
- <link to internal job catalog, if any>

---

*Last verified working: <YYYY-MM-DD>.*
