import { describe, expect, test } from "vitest"
import {
  albumsFrom,
  artistProfile,
  artistsFrom,
  creditsOf,
  listenersFrom,
  matching,
  matchingListeners,
  playsOfArtist,
  plural,
  topTracksFrom,
  withinRange,
} from "./derive"

let nextId = 0

// A play with just enough shape for whichever derive.js function is under
// test — every field can be overridden, so a test only ever states what it
// actually cares about.
function play(overrides = {}) {
  const { track: trackOverrides, listener, played_at, id } = overrides

  return {
    id: id ?? `play-${nextId++}`,
    played_at: played_at ?? "2024-06-15T12:00:00.000Z",
    listener,
    track: {
      spotify_id: `track-${nextId}`,
      name: "Track",
      artists: "Artist",
      album: "Album",
      album_image_url: null,
      ...trackOverrides,
    },
  }
}

describe("withinRange", () => {
  const now = new Date("2024-06-15T12:00:00.000Z").getTime()

  test("'today' keeps only plays from local midnight onward", () => {
    const plays = [
      play({ played_at: "2024-06-15T00:30:00.000Z" }),
      play({ played_at: "2024-06-14T23:00:00.000Z" }),
    ]

    expect(withinRange(plays, "today", now)).toEqual([plays[0]])
  })

  test("'week' keeps the last seven days, today included", () => {
    const plays = [
      play({ played_at: "2024-06-09T00:00:00.000Z" }), // exactly 6 days back
      play({ played_at: "2024-06-08T00:00:00.000Z" }), // 7 days back — out
    ]

    expect(withinRange(plays, "week", now)).toEqual([plays[0]])
  })

  test("'all' returns every play untouched", () => {
    const plays = [play(), play()]
    expect(withinRange(plays, "all", now)).toBe(plays)
  })
})

describe("matchingListeners", () => {
  const listeners = [{ name: "João" }, { name: "Ana Sofía" }]

  test("matches without regard to diacritics", () => {
    expect(matchingListeners(listeners, "joao")).toEqual([listeners[0]])
    expect(matchingListeners(listeners, "sofia")).toEqual([listeners[1]])
  })

  test("returns everyone for a blank query", () => {
    expect(matchingListeners(listeners, "  ")).toBe(listeners)
  })
})

describe("matching", () => {
  const plays = [
    play({ track: { name: "Pyramid Song", artists: "Radiohead", album: "Amnesiac" } }),
    play({ track: { name: "Teardrop", artists: "Massive Attack", album: "Mezzanine" } }),
  ]

  test("matches on track name, artist, or album, case-insensitively", () => {
    expect(matching(plays, "PYRAMID")).toEqual([plays[0]])
    expect(matching(plays, "massive")).toEqual([plays[1]])
    expect(matching(plays, "mezzanine")).toEqual([plays[1]])
  })

  test("returns everything for a blank query", () => {
    expect(matching(plays, "")).toBe(plays)
  })

  test("matches nothing that isn't there", () => {
    expect(matching(plays, "nonexistent")).toEqual([])
  })
})

describe("creditsOf", () => {
  test("prefers artist_list, keyed by id", () => {
    const track = {
      artists: "A, B",
      artist_list: [
        { id: "a1", name: "A", image_url: "a.jpg" },
        { id: "b1", name: "B" },
      ],
    }

    expect(creditsOf(track)).toEqual([
      { key: "a1", id: "a1", name: "A", imageUrl: "a.jpg" },
      { key: "b1", id: "b1", name: "B", imageUrl: null },
    ])
  })

  test("falls back to splitting the display string when there is no artist_list", () => {
    const track = { artists: "Radiohead, Thom Yorke" }

    expect(creditsOf(track)).toEqual([
      { key: "Radiohead", id: null, name: "Radiohead", imageUrl: null },
      { key: "Thom Yorke", id: null, name: "Thom Yorke", imageUrl: null },
    ])
  })

  // Documented, known imperfection of the fallback path: nothing here can
  // tell a real separator from a comma inside one artist's own name.
  test("the fallback splits a comma inside a single artist's name", () => {
    const track = { artists: "Tyler, The Creator" }

    expect(creditsOf(track).map((credit) => credit.name)).toEqual(["Tyler", "The Creator"])
  })

  test("returns nothing for a track with no credits at all", () => {
    expect(creditsOf({ artists: "" })).toEqual([])
  })
})

describe("albumsFrom", () => {
  test("groups plays by album and artist, counting and keeping the latest", () => {
    const older = play({ played_at: "2024-06-14T12:00:00.000Z", track: { album: "Amnesiac", artists: "Radiohead" } })
    const newer = play({ played_at: "2024-06-15T12:00:00.000Z", track: { album: "Amnesiac", artists: "Radiohead" } })
    const other = play({ track: { album: "Mezzanine", artists: "Massive Attack" } })

    const albums = albumsFrom([newer, older, other])

    expect(albums).toHaveLength(2)
    const amnesiac = albums.find((album) => album.name === "Amnesiac")
    expect(amnesiac.count).toBe(2)
    expect(amnesiac.latestPlay).toBe(newer)
  })

  test("skips a play with no album", () => {
    const noAlbum = play({ track: { album: null } })
    expect(albumsFrom([noAlbum])).toEqual([])
  })

  test("respects the limit", () => {
    const plays = [
      play({ track: { album: "One" } }),
      play({ track: { album: "Two" } }),
      play({ track: { album: "Three" } }),
    ]

    expect(albumsFrom(plays, 2)).toHaveLength(2)
  })
})

describe("artistsFrom", () => {
  test("ranks by how often the artist appears", () => {
    const plays = [
      play({ track: { artists: "A", artist_list: [{ id: "a", name: "A" }] } }),
      play({ track: { artists: "A", artist_list: [{ id: "a", name: "A" }] } }),
      play({ track: { artists: "B", artist_list: [{ id: "b", name: "B" }] } }),
    ]

    const artists = artistsFrom(plays)

    expect(artists[0].id).toBe("a")
    expect(artists[0].count).toBe(2)
    expect(artists[1].id).toBe("b")
    expect(artists[1].count).toBe(1)
  })

  test("falls back to the album cover when the artist has no photo of their own", () => {
    const plays = [
      play({
        track: {
          artists: "A",
          artist_list: [{ id: "a", name: "A" }],
          album_image_url: "album-cover.jpg",
        },
      }),
    ]

    expect(artistsFrom(plays)[0].imageUrl).toBe("album-cover.jpg")
  })
})

describe("plural", () => {
  test("uses the singular for exactly one", () => {
    expect(plural(1, "play")).toBe("1 play")
  })

  test("uses the (optionally custom) plural otherwise", () => {
    expect(plural(0, "play")).toBe("0 plays")
    expect(plural(2, "play")).toBe("2 plays")
    expect(plural(2, "story", "stories")).toBe("2 stories")
  })
})

describe("listenersFrom", () => {
  test("gives every roster member an entry, even with zero plays", () => {
    const roster = [{ id: 1, name: "Ana" }, { id: 2, name: "Bea" }]
    const plays = [play({ listener: { id: 1 } })]

    const result = listenersFrom(plays, roster)

    expect(result.map((listener) => listener.count)).toEqual([1, 0])
    expect(result[1].latestPlay).toBeNull()
  })
})

describe("playsOfArtist", () => {
  test("keeps only plays crediting that artist", () => {
    const target = play({ track: { artists: "A", artist_list: [{ id: "a", name: "A" }] } })
    const other = play({ track: { artists: "B", artist_list: [{ id: "b", name: "B" }] } })

    expect(playsOfArtist([target, other], "a")).toEqual([target])
  })
})

describe("topTracksFrom", () => {
  test("ranks distinct tracks by play count", () => {
    const plays = [
      play({ track: { spotify_id: "t1", name: "One" } }),
      play({ track: { spotify_id: "t1", name: "One" } }),
      play({ track: { spotify_id: "t2", name: "Two" } }),
    ]

    const ranked = topTracksFrom(plays)

    expect(ranked[0].track.name).toBe("One")
    expect(ranked[0].count).toBe(2)
    expect(ranked[1].count).toBe(1)
  })
})

describe("artistProfile", () => {
  test("composes counts, top tracks and albums for one artist's plays", () => {
    const plays = [
      play({
        played_at: "2024-06-15T12:00:00.000Z",
        track: { spotify_id: "t1", name: "New", artists: "A", artist_list: [{ id: "a", name: "A", image_url: "a.jpg" }], album: "Latest" },
      }),
      play({
        played_at: "2024-06-01T12:00:00.000Z",
        track: { spotify_id: "t2", name: "Old", artists: "A", artist_list: [{ id: "a", name: "A" }], album: "First" },
      }),
    ]

    const profile = artistProfile(plays, "a")

    expect(profile.name).toBe("A")
    expect(profile.imageUrl).toBe("a.jpg")
    expect(profile.count).toBe(2)
    expect(profile.trackCount).toBe(2)
    expect(profile.albumCount).toBe(2)
    // Plays arrive newest-first, so the oldest — the first play — is the last one.
    expect(profile.firstPlayedAt).toBe("2024-06-01T12:00:00.000Z")
  })

  test("falls back to the given name, then the key, when nothing was ever played", () => {
    expect(artistProfile([], "artist-key", { name: "Given Name" }).name).toBe("Given Name")
    expect(artistProfile([], "artist-key").name).toBe("artist-key")
  })
})
