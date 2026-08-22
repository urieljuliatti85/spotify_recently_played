#!/usr/bin/env node
// Launch and drive the Recently Played app headlessly.
//
// Why this exists rather than "run bin/dev and open a browser":
//
//   * The assets are copied out to public/driver/ before being served. Vite
//     Ruby installs a proxy middleware that owns the /vite-dev/ prefix whenever
//     a dev server is reachable, and it answers 404 for files it does not know
//     about — including the very files `vite build` just wrote to
//     public/vite-dev/. Serving from a prefix it does not claim works whether
//     or not somebody has bin/dev running.
//
//   * Headless Chrome does not mount this app when it is served through the
//     Vite dev server. Every module arrives as its own request and the page
//     is still resolving the graph when the screenshot is taken — you get a
//     blank frame, and it fails the same way on the home page, so it is not
//     any one view's fault. The fix is to build the bundle first and load it
//     from a static page (`preview`), which is one module, not ninety.
//
//   * bin/dev also starts bin/jobs, which syncs against the real Spotify API
//     using the owner's stored token. A screenshot run has no business
//     spending someone's API quota, so this never starts it.
//
//   * It runs on its own port with its own pidfile and only ever kills the
//     pid it wrote. Reaching for `pkill -f "rails server"` kills the
//     developer's own bin/dev, and the stale tmp/pids/server.pid it leaves
//     behind then blocks the next boot.
//
// Usage:
//   node .claude/skills/run-spotify-recently-played/driver.mjs <command>
//
//   up                 build assets, write the preview page, start Rails
//   down               stop the server this driver started
//   seed               add demo listeners + plays (marked DEMO-, no network)
//   unseed             remove only the DEMO- rows
//   shot <view> [out]  screenshot one tab; asserts the app actually mounted
//   api <path>         GET a JSON endpoint off the running server
//   smoke              up + seed + shot the offline tabs + unseed + down
//
//   Views: overview | tracks | artists | listeners | playlists
//   (playlists calls Spotify live, so it is not in `smoke` — see SKILL.md)

import { execFileSync, spawn } from "node:child_process"
import {
  cpSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..")
const PORT = Number(process.env.DRIVER_PORT ?? 3010)
const BASE = `http://127.0.0.1:${PORT}`
const OUT = process.env.DRIVER_OUT ?? join(ROOT, "tmp", "driver")
const PIDFILE = join(OUT, "rails.pid")
const LOGFILE = join(OUT, "rails.log")
const PREVIEW = join(ROOT, "public", "preview.html")
// Vite's own output dir, then where we copy it so vite_ruby's proxy cannot
// intercept the requests.
const VITE_OUT = join(ROOT, "public", "vite-dev")
const ASSET_DIR = join(ROOT, "public", "driver")
const VIEWS = ["overview", "tracks", "artists", "listeners", "playlists"]
// Everything except playlists renders from the local database. The playlists
// tab calls Spotify live, so it needs real credentials and a real linked
// account — it is not part of the offline smoke.
const OFFLINE_VIEWS = VIEWS.filter((v) => v !== "playlists")

const sh = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { cwd: ROOT, encoding: "utf8", stdio: "pipe", ...opts })

const log = (...a) => console.log("[driver]", ...a)
// Throws rather than exiting: `smoke` has to reach its `finally` and put the
// database and the server back, even when a screenshot fails.
class DriverError extends Error {}
const die = (msg) => {
  throw new DriverError(msg)
}

// --- Chrome ----------------------------------------------------------------
// No chromium-cli / playwright / puppeteer in this project, but a desktop
// Chrome is enough: it screenshots and dumps DOM straight from the CLI.
function chrome() {
  if (process.env.CHROME) return process.env.CHROME

  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ]
  const found = candidates.find((p) => existsSync(p))
  if (found) return found

  for (const name of ["google-chrome", "chromium", "chromium-browser"]) {
    try {
      return sh("command", ["-v", name], { shell: true }).trim()
    } catch {
      /* keep looking */
    }
  }
  die("no Chrome/Chromium found — set CHROME=/path/to/binary")
}

const CHROME_FLAGS = [
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--hide-scrollbars",
  // Without a virtual clock the page is screenshotted before React has
  // fetched /api/status and /api/plays, and the cards render empty.
  "--virtual-time-budget=20000",
]

// --- server ----------------------------------------------------------------
async function waitFor(url, seconds = 60) {
  const deadline = Date.now() + seconds * 1000
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url)
      if (res.ok) return true
    } catch {
      /* not listening yet */
    }
    await new Promise((r) => setTimeout(r, 300))
  }
  return false
}

function runningPid() {
  if (!existsSync(PIDFILE)) return null
  const pid = Number(readFileSync(PIDFILE, "utf8").trim())
  if (!pid) return null
  try {
    process.kill(pid, 0)
    return pid
  } catch {
    return null
  }
}

function buildAssets() {
  log("building assets (development mode) …")
  sh("bin/vite", ["build", "--mode", "development"], { stdio: "inherit" })

  const manifestPath = join(VITE_OUT, ".vite", "manifest.json")
  if (!existsSync(manifestPath)) die(`no manifest at ${manifestPath}`)

  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
  const entry = Object.entries(manifest).find(([k]) => k.endsWith("entrypoints/application.jsx"))?.[1]
  if (!entry) die("manifest has no entrypoints/application.jsx")

  // Out from under the proxy's prefix, then rewrite the handful of absolute
  // /vite-dev/ URLs Vite baked into the bundle so they follow.
  rmSync(ASSET_DIR, { recursive: true, force: true })
  cpSync(join(VITE_OUT, "assets"), join(ASSET_DIR, "assets"), { recursive: true })
  for (const file of readdirSync(join(ASSET_DIR, "assets"))) {
    if (!/\.(js|css)$/.test(file)) continue
    const path = join(ASSET_DIR, "assets", file)
    writeFileSync(path, readFileSync(path, "utf8").replaceAll("/vite-dev/", "/driver/"))
  }

  const css = (entry.css ?? []).map((c) => `<link rel="stylesheet" href="/driver/${c}">`).join("\n")
  // Mirrors app/views/pages/index.html.erb: the entrypoint reads both data
  // attributes off #app.
  writeFileSync(
    PREVIEW,
    `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>preview</title>
${css}
</head><body>
<div id="app" data-flash="" data-connect-path="/spotify/connect"></div>
<script type="module" src="/driver/${entry.file}"></script>
</body></html>
`
  )
  log(`preview page -> public/preview.html (bundle ${entry.file})`)
}

async function up() {
  mkdirSync(OUT, { recursive: true })

  if (runningPid()) {
    log(`already up on ${BASE} (pid ${runningPid()})`)
    return
  }
  buildAssets()

  log(`starting Rails on ${PORT} (no bin/jobs — it would hit the real Spotify API) …`)
  // Into a file, not the parent's stdout: development logging is per-request
  // and verbose enough to bury the driver's own output during a smoke run.
  const logFd = openSync(LOGFILE, "a")
  const child = spawn(
    "bin/rails",
    ["server", "-p", String(PORT), "-e", "development", "-P", PIDFILE],
    { cwd: ROOT, detached: true, stdio: ["ignore", logFd, logFd] }
  )
  child.unref()

  // Poll rather than sleep: screenshotting a half-booted Rails gets a 404 on
  // /api/plays and the UI renders "Couldn't load the tracks".
  if (!(await waitFor(`${BASE}/up`, 90))) die(`Rails did not answer ${BASE}/up — see ${LOGFILE}`)
  if (!(await waitFor(`${BASE}/api/status`, 30))) die("/api/status never became ready")

  log(`up on ${BASE}`)
}

function down() {
  const pid = runningPid()
  if (!pid) {
    log("nothing this driver started is running")
  } else {
    // Only ever our own pid. Never a pattern match.
    process.kill(pid, "SIGTERM")
    log(`stopped Rails (pid ${pid})`)
  }
  rmSync(PIDFILE, { force: true })
  rmSync(PREVIEW, { force: true })
  rmSync(VITE_OUT, { recursive: true, force: true })
  rmSync(ASSET_DIR, { recursive: true, force: true })
  log("removed public/preview.html, public/vite-dev and public/driver")
}

// --- demo data -------------------------------------------------------------
// A clean clone has no Spotify credentials and an empty database, so the UI
// has nothing to render. This fabricates a feed locally — no OAuth, no
// network — and tags every row so unseed can find exactly them again.
const SEED_RUBY = `
owner = SpotifyAccount.find_or_create_by!(spotify_user_id: "DEMO-owner") do |a|
  a.display_name = "Demo Owner"
  a.owner = SpotifyAccount.where(owner: true).none?
  a.refresh_token = "demo"
  a.last_synced_at = Time.current
end
friend = SpotifyAccount.find_or_create_by!(spotify_user_id: "DEMO-friend") do |a|
  a.display_name = "Demo Friend"
  a.refresh_token = "demo"
  a.last_synced_at = Time.current
end

CATALOG = [
  [ "Pyramid Song", "Radiohead", "Amnesiac" ],
  [ "Teardrop", "Massive Attack", "Mezzanine" ],
  [ "Duvet", "Boa", "Twilight" ],
  [ "Cissy Strut", "The Meters", "The Meters" ],
  [ "Windowlicker", "Aphex Twin", "Windowlicker" ],
  [ "Xtal", "Aphex Twin", "Selected Ambient Works" ]
]

tracks = CATALOG.each_with_index.map do |(name, artist, album), i|
  Track.upsert_from_spotify!(
    "id" => "DEMO-t#{i}", "name" => name,
    "artists" => [ { "id" => "DEMO-a#{artist.parameterize}", "name" => artist } ],
    "album" => { "name" => album, "images" => [] },
    "duration_ms" => 180_000 + i * 20_000, "explicit" => false
  )
end

[ [ owner, 24, 0 ], [ friend, 9, 7 ] ].each do |account, count, offset|
  count.times do |i|
    played = (offset + i * 13 + 2).minutes.ago.round
    next if account.plays.exists?(played_at: played)
    account.plays.create!(track: tracks[(i * 3 + offset) % tracks.size], played_at: played)
  end
end

puts "seeded: #{SpotifyAccount.where("spotify_user_id LIKE 'DEMO-%'").count} listener(s), " \\
     "#{Play.joins(:spotify_account).where("spotify_accounts.spotify_user_id LIKE 'DEMO-%'").count} play(s)"
`

const UNSEED_RUBY = `
scope = SpotifyAccount.where("spotify_user_id LIKE 'DEMO-%'")
plays = Play.where(spotify_account_id: scope.select(:id)).count
scope.destroy_all
Track.where("spotify_id LIKE 'DEMO-%'").destroy_all
Artist.where("spotify_id LIKE 'DEMO-%'").destroy_all
puts "unseeded: #{plays} play(s); real data untouched " \\
     "(#{SpotifyAccount.count} account(s), #{Play.count} play(s) remain)"
`

const runner = (ruby) => sh("bin/rails", ["runner", ruby], { stdio: "inherit" })

// --- screenshots -----------------------------------------------------------
function shot(view = "listeners", out) {
  if (!VIEWS.includes(view)) die(`unknown view ${view} — one of ${VIEWS.join(", ")}`)
  if (!runningPid()) die("server is not up — run `up` first")

  mkdirSync(OUT, { recursive: true })
  const file = out ? resolve(out) : join(OUT, `${view}.png`)
  const url = `${BASE}/preview.html?view=${view}`
  const bin = chrome()

  // Assert the app mounted before trusting the pixels: a blank frame and a
  // correctly-rendered one are both "exit 0" as far as Chrome is concerned.
  const dom = sh(bin, [...CHROME_FLAGS, "--dump-dom", url], { stdio: ["ignore", "pipe", "ignore"] })
  if (!dom.includes('class="sidebar"')) {
    writeFileSync(join(OUT, `${view}.dom.html`), dom)
    die(`app did not mount at ${url} — DOM saved to ${join(OUT, `${view}.dom.html`)}`)
  }
  const failed = dom.includes("Couldn&#039;t load") || dom.includes("Couldn't load")
  if (failed && view !== "playlists") {
    die(`app mounted but an API call failed at ${url} — check ${LOGFILE}`)
  }
  if (failed) {
    // Expected without Spotify credentials; the screenshot still shows the
    // error state, which is the real behaviour on a clean machine.
    log("note: playlists could not reach Spotify — screenshotting its error state")
  }

  sh(bin, [...CHROME_FLAGS, "--window-size=1500,1000", `--screenshot=${file}`, url], {
    stdio: ["ignore", "ignore", "ignore"],
  })
  const bytes = statSync(file).size
  // A blank 1500x1000 frame lands around 10 KB; a rendered page is 100 KB+.
  if (bytes < 30_000) die(`screenshot looks blank (${bytes} bytes): ${file}`)

  log(`${view} -> ${file} (${Math.round(bytes / 1024)} KB)`)
  return file
}

async function api(path) {
  if (!runningPid()) die("server is not up — run `up` first")
  const res = await fetch(`${BASE}${path.startsWith("/") ? path : `/${path}`}`, {
    headers: { Accept: "application/json" },
  })
  console.log(`HTTP ${res.status}`)
  console.log(JSON.stringify(await res.json(), null, 2))
}

// --- main ------------------------------------------------------------------
const [command, ...rest] = process.argv.slice(2)

async function main() {
  switch (command) {
    case "up":
      await up()
      break
    case "down":
      down()
      break
    case "seed":
      runner(SEED_RUBY)
      break
    case "unseed":
      runner(UNSEED_RUBY)
      break
    case "shot":
      shot(rest[0], rest[1])
      break
    case "api":
      await api(rest[0] ?? "/api/status")
      break
    case "smoke": {
      await up()
      runner(SEED_RUBY)
      try {
        for (const view of OFFLINE_VIEWS) shot(view)
      } finally {
        // Runs even when a shot fails, which is the whole reason `die` throws
        // instead of calling process.exit: a failed smoke must still hand back
        // a clean database and a stopped server.
        runner(UNSEED_RUBY)
        down()
      }
      log(`smoke OK — screenshots in ${OUT} (playlists skipped: needs live Spotify)`)
      break
    }
    default:
      console.log(readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 35).join("\n"))
      process.exitCode = command ? 1 : 0
  }
}

try {
  await main()
} catch (error) {
  if (error instanceof DriverError) {
    console.error("[driver] FAIL:", error.message)
  } else {
    console.error("[driver] FAIL:", error.stack ?? error)
  }
  process.exitCode = 1
}
