# Observability on Railway

Railway is a PaaS — no SSH access to a host, so `observability/docker-compose.yml`
(self-hosted Prometheus + Grafana) doesn't apply here directly: each service
is its own isolated container. The stack that fits Railway instead is a
[Grafana Alloy](https://grafana.com/docs/alloy/latest/) service that scrapes
this app's `/metrics` over Railway's **private network** and forwards it to
[Grafana Cloud](https://grafana.com/products/cloud/)'s hosted Prometheus +
Grafana (there's a free tier). Nothing here is exposed publicly — Alloy talks
to the app privately, and only the outbound `remote_write` to Grafana Cloud
leaves Railway, over HTTPS.

Config validated locally against a real `/metrics` (Grafana Alloy `v1.5.1`,
scrape target reported `health: up`) — the Grafana Cloud side (steps 1 and 4
below) is not, since that needs a real account.

## 1. Grafana Cloud: get a Prometheus remote_write endpoint

Free account at [grafana.com](https://grafana.com/auth/sign-up/create-user) →
your stack's **Connections → Add new connection → Prometheus** page. It shows:

- **Remote Write URL** (`GRAFANA_CLOUD_PROMETHEUS_URL`) — looks like
  `https://prometheus-prod-##-prod-##-####.grafana.net/api/prom/push`
- **Username** (`GRAFANA_CLOUD_PROMETHEUS_USERNAME`) — a numeric stack id
- Generate an **API token** with the `metrics:write` scope
  (`GRAFANA_CLOUD_PROMETHEUS_API_KEY`)

## 2. Railway: add the Alloy service

In the **same Railway project** as this app (so private networking applies):

1. **New Service → GitHub Repo** → this repository.
2. **Settings → Root Directory** → `observability/railway/alloy` (Railway
   builds the `Dockerfile` there — `grafana/alloy` with the scrape config
   baked in; see that file's comments).
3. Leave it with **no public domain** — Alloy never needs to be reachable
   from outside Railway.
4. **Variables**, using Railway's `${{ServiceName.VAR}}` reference syntax so
   nothing is copy-pasted by hand (swap `spotify-recently-played` for
   whatever your Rails service is actually named in this project):

   | Variable | Value |
   | --- | --- |
   | `APP_METRICS_HOST` | `${{spotify-recently-played.RAILWAY_PRIVATE_DOMAIN}}` |
   | `APP_METRICS_PORT` | `${{spotify-recently-played.PORT}}` |
   | `ADMIN_PASSWORD` | `${{spotify-recently-played.ADMIN_PASSWORD}}` |
   | `GRAFANA_CLOUD_PROMETHEUS_URL` | from step 1 |
   | `GRAFANA_CLOUD_PROMETHEUS_USERNAME` | from step 1 |
   | `GRAFANA_CLOUD_PROMETHEUS_API_KEY` | from step 1 |

5. Deploy. Alloy scrapes every 30s (`config.alloy`); within a minute or two,
   Grafana Cloud's **Explore** page should answer a query for
   `spotify_requests_total`.

## 3. Import the dashboard

Grafana Cloud → **Dashboards → New → Import** → upload
`../grafana/dashboards/spotify_recently_played.json` (the same file the
self-hosted stack provisions automatically) → when prompted, point it at
your Grafana Cloud Prometheus datasource.

## Alternative: Metrics Endpoint Integration (no Alloy service)

Grafana Cloud can also scrape `/metrics` itself, with no Alloy service to deploy
at all: **Connections → Add new connection → Metrics Endpoint** (not the
"Prometheus" connection used for `remote_write` above). It asks for a scrape
job URL and Basic/Bearer credentials, then polls every 60s.

This trades away the private-network isolation the Alloy setup above gets for
free — Grafana Cloud isn't inside Railway, so it has to reach the app's
**public** domain instead of `RAILWAY_PRIVATE_DOMAIN`, sending the
`ADMIN_PASSWORD` Basic Auth credential over Railway's edge on every scrape.
That's the exact thing note 2 below says to avoid when it can be avoided — here
it can't, since there's no private path in from outside Railway. It's still
safe (the public domain is HTTPS, and `/metrics` is Basic-Auth-gated same as
always), just a different trade: zero infrastructure to run, in exchange for
credentials leaving the private network.

1. Grafana Cloud → **Connections → Add new connection → Metrics Endpoint**.
2. **Scrape Job URL**: `https://<this app's public Railway domain>/metrics`
3. **Auth type**: Basic — any username, password = `ADMIN_PASSWORD`.
4. Save. Within a minute or two, the job reports `up` and
   `spotify_requests_total` is queryable in Explore.
5. Import the dashboard as in step 3 above.

Prefer this over the Alloy service when you don't want a second Railway
service to babysit and don't mind the credential trade-off; prefer Alloy when
keeping `/metrics` traffic off the public edge matters more.

## Notes

- `ADMIN_PASSWORD` referenced from the Rails service keeps the two in sync
  automatically — if it ever changes there, this service picks it up on its
  next deploy without editing anything here.
- `scheme = "http"` in `config.alloy` is intentional and safe: that request
  never leaves Railway's private network. Don't point `APP_METRICS_HOST` at
  the public domain instead — it would also work, but sends Basic Auth
  credentials over Railway's edge for no reason.
- This only ships the two app-specific groups plus whatever `yabeda-rails`
  adds — see `config/initializers/yabeda.rb` and the "Prometheus" section of
  the main README for what's actually collected.
