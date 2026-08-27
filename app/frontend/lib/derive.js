// Everything the shelves and filters show is derived from the plays already in
// memory — the API only serves the raw feed, so there is nothing to fetch.

const DAY_MS = 24 * 60 * 60 * 1000

export const RANGES = [
  { id: "today", label: "Today" },
  { id: "week", label: "This Week" },
  { id: "all", label: "All Time" },
]

function startOfToday(now) {
  const start = new Date(now)
  start.setHours(0, 0, 0, 0)
  return start.getTime()
}

export function withinRange(plays, rangeId, now = Date.now()) {
  if (rangeId === "all") return plays

  const floor = rangeId === "today" ? startOfToday(now) : startOfToday(now) - 6 * DAY_MS

  return plays.filter((play) => new Date(play.played_at).getTime() >= floor)
}

// Names are matched without accents so "joao" finds "João" and "ana" finds
// "Ana Sofía" — a filter that demands the right diacritics is a filter that
// fails the names most likely to have them.
function fold(text) {
  return (text ?? "")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .trim()
    .toLowerCase()
}

/** Listeners whose name matches, for the filter on the Listeners tab. */
export function matchingListeners(listeners, query) {
  const needle = fold(query)
  if (!needle) return listeners

  return listeners.filter((listener) => fold(listener.name).includes(needle))
}

export function matching(plays, query) {
  const needle = query.trim().toLowerCase()
  if (!needle) return plays

  return plays.filter((play) => {
    const { name, artists, album } = play.track
    return `${name} ${artists} ${album ?? ""}`.toLowerCase().includes(needle)
  })
}

/**
 * The credits on a track. `artist_list` is the real thing: one record per
 * artist, keyed by the id Spotify knows them by.
 *
 * Tracks stored before artists were modelled have no list, so the joined
 * display string is split as a fallback. Those credits have no id and fall
 * back to the name as their key — which is exactly where a name containing a
 * comma ("Tyler, The Creator") splits into two, until `bin/rails
 * spotify:backfill_artists` has recovered the real credits.
 */
export function creditsOf(track) {
  const list = track.artist_list

  if (Array.isArray(list) && list.length > 0) {
    return list.map((artist) => ({
      key: artist.id ?? artist.name,
      id: artist.id ?? null,
      name: artist.name,
      imageUrl: artist.image_url ?? null,
    }))
  }

  return (track.artists ?? "")
    .split(",")
    .map((name) => name.trim())
    .filter(Boolean)
    .map((name) => ({ key: name, id: null, name, imageUrl: null }))
}

export function albumsFrom(plays, limit = 20) {
  const albums = new Map()

  for (const play of plays) {
    const { album, album_image_url: image } = play.track
    if (!album) continue

    const key = `${album}::${play.track.artists}`
    const existing = albums.get(key)

    if (existing) {
      existing.count += 1
      existing.plays.push(play)
      continue
    }

    albums.set(key, {
      key,
      albumId: play.track.album_spotify_id,
      name: album,
      artists: play.track.artists,
      imageUrl: image,
      latestPlay: play,
      count: 1,
      plays: [play],
    })
  }

  return [...albums.values()].slice(0, limit)
}

/**
 * Artists ranked by how often they show up in the given plays. The photo is
 * the artist's own where the backfill has fetched one, and the cover of an
 * album they turn up on until then.
 */
export function artistsFrom(plays, limit = 20) {
  const artists = new Map()

  for (const play of plays) {
    for (const credit of creditsOf(play.track)) {
      const existing = artists.get(credit.key)

      if (existing) {
        existing.count += 1
        existing.photo ||= credit.imageUrl
        existing.cover ||= play.track.album_image_url
        continue
      }

      artists.set(credit.key, {
        key: credit.key,
        id: credit.id,
        name: credit.name,
        photo: credit.imageUrl,
        cover: play.track.album_image_url,
        latestPlay: play,
        count: 1,
      })
    }
  }

  return [...artists.values()]
    .sort((a, b) => b.count - a.count)
    .slice(0, limit)
    .map(({ photo, cover, ...artist }) => ({ ...artist, imageUrl: photo ?? cover ?? null }))
}

export function plural(count, singular, plural = `${singular}s`) {
  return `${count.toLocaleString("en-US")} ${count === 1 ? singular : plural}`
}

/**
 * What each listener has been playing, derived from the feed already in
 * memory. Everyone on the roster gets an entry, including whoever has nothing
 * in the current range — "Ana played nothing this week" is worth showing, and
 * dropping her card would read as her having left.
 *
 * Plays arrive newest-first and the grouping preserves that, so `latestPlay` is
 * the head of each bucket rather than something that has to be searched for.
 */
export function listenersFrom(plays, roster, { artists = 4, tracks = 3 } = {}) {
  const grouped = new Map(roster.map((listener) => [listener.id, []]))

  for (const play of plays) {
    grouped.get(play.listener?.id)?.push(play)
  }

  return roster.map((listener) => {
    const own = grouped.get(listener.id) ?? []

    return {
      ...listener,
      plays: own,
      count: own.length,
      latestPlay: own[0] ?? null,
      topArtists: artistsFrom(own, artists),
      topTracks: topTracksFrom(own, tracks),
    }
  })
}

/** Every play the given artist appears on, still newest-first. */
export function playsOfArtist(plays, key) {
  return plays.filter((play) => creditsOf(play.track).some((credit) => credit.key === key))
}

/**
 * Distinct tracks ranked by how often they were played. Keyed on the Spotify
 * id, with the name as a fallback for the rare track that arrives without one.
 */
export function topTracksFrom(plays, limit = 10) {
  const tracks = new Map()

  for (const play of plays) {
    const { track } = play
    const trackKey = track.spotify_id ?? `${track.name}::${track.album ?? ""}`
    const existing = tracks.get(trackKey)

    if (existing) {
      existing.count += 1
      continue
    }

    tracks.set(trackKey, { key: trackKey, track, latestPlay: play, count: 1 })
  }

  return [...tracks.values()].sort((a, b) => b.count - a.count).slice(0, limit)
}

/**
 * Everything the artist page shows, derived from the plays already in memory.
 * Counts are taken before the display slices so the header can say "42 tracks"
 * while the list below shows only the top ten.
 *
 * `name` is the label to fall back to when the range hides every play the
 * artist appears on, leaving nothing to read their name off.
 */
export function artistProfile(plays, key, { name = null, tracks = 10, albums = 12 } = {}) {
  const own = playsOfArtist(plays, key)
  const credits = own.map((play) => creditsOf(play.track).find((credit) => credit.key === key))
  const ranked = topTracksFrom(own, Infinity)
  const records = albumsFrom(own, Infinity)

  return {
    key,
    id: credits[0]?.id ?? null,
    name: credits[0]?.name ?? name ?? key,
    imageUrl:
      credits.find((credit) => credit?.imageUrl)?.imageUrl ??
      own[0]?.track.album_image_url ??
      null,
    plays: own,
    count: own.length,
    trackCount: ranked.length,
    albumCount: records.length,
    topTracks: ranked.slice(0, tracks),
    albums: records.slice(0, albums),
    latestPlay: own[0] ?? null,
    firstPlayedAt: own.at(-1)?.played_at ?? null,
  }
}
