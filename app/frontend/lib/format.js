const RELATIVE = new Intl.RelativeTimeFormat("en-US", { numeric: "auto" })
const TIME = new Intl.DateTimeFormat("en-US", { hour: "2-digit", minute: "2-digit" })
const LONG_DAY = new Intl.DateTimeFormat("en-US", { weekday: "long", day: "numeric", month: "long" })
const WITH_YEAR = new Intl.DateTimeFormat("en-US", { day: "numeric", month: "long", year: "numeric" })

const MINUTE = 60
const HOUR = MINUTE * 60
const DAY = HOUR * 24

export function timeOfDay(isoString) {
  return TIME.format(new Date(isoString))
}

export function relativeTime(isoString, now = Date.now()) {
  const seconds = Math.round((new Date(isoString).getTime() - now) / 1000)
  const elapsed = Math.abs(seconds)

  if (elapsed < MINUTE) return "just now"
  if (elapsed < HOUR) return RELATIVE.format(Math.round(seconds / MINUTE), "minute")
  if (elapsed < DAY) return RELATIVE.format(Math.round(seconds / HOUR), "hour")
  if (elapsed < DAY * 7) return RELATIVE.format(Math.round(seconds / DAY), "day")

  // Older than a week the day heading already carries the date, so a relative
  // label would only repeat it.
  return null
}

// Groups plays under "Today" / "Yesterday" / a written-out date.
export function dayKey(isoString) {
  const date = new Date(isoString)
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`
}

export function dayLabel(isoString, now = new Date()) {
  const date = new Date(isoString)
  const today = dayKey(now.toISOString())
  const yesterday = dayKey(new Date(now.getTime() - DAY * 1000).toISOString())

  if (dayKey(isoString) === today) return "Today"
  if (dayKey(isoString) === yesterday) return "Yesterday"
  if (date.getFullYear() === now.getFullYear()) return LONG_DAY.format(date)

  return WITH_YEAR.format(date)
}

export function duration(ms) {
  if (!ms) return null

  const totalSeconds = Math.round(ms / 1000)
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = String(totalSeconds % 60).padStart(2, "0")

  return `${minutes}:${seconds}`
}

// lrclib's synced format: one "[mm:ss.xx]text" tag per line. A line with no
// tag (or no text after it) carries no timing information and is dropped —
// activeLyricIndex only needs to know the last real line whose timestamp has
// passed, and a blank line can't be that.
const LRC_LINE = /^\[(\d{2}):(\d{2}(?:\.\d{1,3})?)\](.*)$/

export function parseSyncedLyrics(text) {
  if (!text) return []

  return text
    .split("\n")
    .map((line) => LRC_LINE.exec(line))
    .filter((match) => match && match[3].trim())
    .map((match) => ({ time: Number(match[1]) * 60 + Number(match[2]), text: match[3].trim() }))
}

// The index of the last line whose timestamp has passed — -1 before the
// first line, or when there is nothing to sync.
export function activeLyricIndex(lines, positionMs) {
  const positionSeconds = positionMs / 1000
  let active = -1

  for (let i = 0; i < lines.length; i++) {
    if (lines[i].time > positionSeconds) break
    active = i
  }

  return active
}

export function groupByDay(plays) {
  const groups = []

  for (const play of plays) {
    const key = dayKey(play.played_at)
    const last = groups.at(-1)

    if (last && last.key === key) {
      last.plays.push(play)
    } else {
      groups.push({ key, label: dayLabel(play.played_at), plays: [play] })
    }
  }

  return groups
}
