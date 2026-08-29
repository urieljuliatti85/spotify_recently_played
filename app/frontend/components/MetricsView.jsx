import { useCallback, useEffect, useState } from "react"
import { fetchMetrics } from "../lib/api"

// Sums duplicate rows by `key`, since a series can arrive split across
// several labels the chart doesn't care about (e.g. one row per status code
// for the same endpoint).
function groupSum(rows, key) {
  const totals = new Map()
  for (const row of rows) {
    const label = row[key] || "(none)"
    totals.set(label, (totals.get(label) ?? 0) + row.count)
  }
  return [...totals.entries()]
    .map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count)
}

// One row per endpoint/controller, each status/outcome kept as its own
// segment so a bar can show "mostly fine, a sliver of failures" at a glance.
function groupSegments(rows, key, segmentKey) {
  const byLabel = new Map()
  for (const row of rows) {
    const label = row[key] || "(none)"
    const segments = byLabel.get(label) ?? new Map()
    const segmentLabel = row[segmentKey] || "(none)"
    segments.set(segmentLabel, (segments.get(segmentLabel) ?? 0) + row.count)
    byLabel.set(label, segments)
  }

  return [...byLabel.entries()]
    .map(([label, segments]) => ({
      label,
      count: [...segments.values()].reduce((sum, value) => sum + value, 0),
      segments: [...segments.entries()].map(([segmentLabel, count]) => ({ label: segmentLabel, count })),
    }))
    .sort((a, b) => b.count - a.count)
}

// Success-ish segment labels get the steel tone; anything else (a status
// code that isn't 2xx, an exception class name) reads as trouble.
function isHealthy(label) {
  return label === "success" || /^[23]\d\d$/.test(label)
}

function BarSegments({ rows, unit }) {
  const max = Math.max(1, ...rows.map((row) => row.count))

  return (
    <ul className="metrics-bars">
      {rows.map((row) => (
        <li key={row.label} className="metrics-bars__row">
          <span className="metrics-bars__label" title={row.label}>{row.label}</span>
          <span className="metrics-bars__track">
            {row.segments.map((segment) => (
              <span
                key={segment.label}
                className={`metrics-bars__fill ${isHealthy(segment.label) ? "" : "metrics-bars__fill--bad"}`}
                style={{ width: `${(segment.count / max) * 100}%` }}
                title={`${segment.label}: ${segment.count}`}
              />
            ))}
          </span>
          <span className="metrics-bars__value">
            {row.count}
            {unit ? ` ${unit}` : ""}
          </span>
        </li>
      ))}
    </ul>
  )
}

function LatencyList({ rows }) {
  const sorted = [...rows].sort((a, b) => b.avg_seconds - a.avg_seconds)
  const max = Math.max(0.001, ...sorted.map((row) => row.avg_seconds))

  return (
    <ul className="metrics-bars">
      {sorted.map((row) => (
        <li key={row.label} className="metrics-bars__row">
          <span className="metrics-bars__label" title={row.label}>{row.label}</span>
          <span className="metrics-bars__track">
            <span className="metrics-bars__fill" style={{ width: `${(row.avg_seconds / max) * 100}%` }} />
          </span>
          <span className="metrics-bars__value">
            {Math.round(row.avg_seconds * 1000)}ms
            <span className="metrics-bars__count"> ({row.count})</span>
          </span>
        </li>
      ))}
    </ul>
  )
}

function Panel({ title, hint, empty, children }) {
  return (
    <section className="metrics-panel">
      <header className="metrics-panel__head">
        <h2>{title}</h2>
        {hint && <p className="section__hint">{hint}</p>}
      </header>
      {empty ? <p className="section__hint">Nothing recorded yet.</p> : children}
    </section>
  )
}

export default function MetricsView() {
  const [state, setState] = useState("loading")
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  const load = useCallback(() => {
    setState("loading")
    setError(null)
    fetchMetrics()
      .then((payload) => {
        setData(payload)
        setState("ready")
      })
      .catch((cause) => {
        setError(cause)
        setState("error")
      })
  }, [])

  useEffect(() => { load() }, [load])

  const spotifyRequests = data ? groupSegments(data.spotify_requests, "endpoint", "status") : []
  const syncRuns = data ? groupSegments(data.sync_runs, "listener", "outcome") : []
  const playsImported = data ? groupSum(data.sync_plays_imported, "listener") : []
  const railsRequests = data
    ? groupSegments(
        data.rails_requests.map((row) => ({ ...row, action: `${row.controller}#${row.action}` })),
        "action",
        "status"
      )
    : []

  return (
    <section className="section metrics">
      <header className="section__head">
        <div>
          <h1 className="section__title">Metrics</h1>
          <p className="section__hint">
            Counted since this server process last booted — the same numbers <code>GET /metrics</code> exposes
            for Prometheus, reshaped for a browser.
          </p>
        </div>
        <button type="button" className="btn btn--outline" onClick={load} disabled={state === "loading"}>
          {state === "loading" ? "Loading…" : "Refresh"}
        </button>
      </header>

      {state === "error" && (
        <p className="section__hint">{error?.message || "Couldn't load metrics."}</p>
      )}

      {data && (
        <div className="metrics-grid">
          <Panel
            title="Spotify API requests"
            hint="By endpoint — a burst here is what trips the 60/min public rate limit and can stall the sync."
            empty={spotifyRequests.length === 0}
          >
            <BarSegments rows={spotifyRequests} unit="req" />
          </Panel>

          <Panel title="Spotify API latency" hint="Average response time per endpoint." empty={data.spotify_latency.length === 0}>
            <LatencyList rows={data.spotify_latency.map((row) => ({ ...row, label: row.endpoint }))} />
          </Panel>

          <Panel
            title="Sync runs"
            hint="SyncRecentlyPlayedJob outcomes per listener — a red sliver is a listener whose sync is failing."
            empty={syncRuns.length === 0}
          >
            <BarSegments rows={syncRuns} />
          </Panel>

          <Panel title="Plays imported" hint="Total plays SyncRecentlyPlayedJob has stored per listener." empty={playsImported.length === 0}>
            <ul className="metrics-bars">
              {playsImported.map((row) => (
                <li key={row.label} className="metrics-bars__row">
                  <span className="metrics-bars__label" title={row.label}>{row.label}</span>
                  <span className="metrics-bars__track">
                    <span
                      className="metrics-bars__fill"
                      style={{ width: `${(row.count / Math.max(1, ...playsImported.map((r) => r.count))) * 100}%` }}
                    />
                  </span>
                  <span className="metrics-bars__value">{row.count}</span>
                </li>
              ))}
            </ul>
          </Panel>

          <Panel title="HTTP requests" hint="By controller#action." empty={railsRequests.length === 0}>
            <BarSegments rows={railsRequests} unit="req" />
          </Panel>

          <Panel title="HTTP latency" hint="Average response time per controller#action." empty={data.rails_latency.length === 0}>
            <LatencyList
              rows={data.rails_latency.map((row) => ({ ...row, label: `${row.controller}#${row.action}` }))}
            />
          </Panel>
        </div>
      )}
    </section>
  )
}
