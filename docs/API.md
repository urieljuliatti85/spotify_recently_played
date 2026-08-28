# API reference

Detail behind the [route table in the README](../README.md#routes): params and
response shape for every `/api/*` endpoint. All of it is public, unauthenticated
JSON, and all of it counts against the 60-requests-per-minute cap in
`Api::BaseController` (see the README for why).

Errors, where an endpoint can hit Spotify or the Discogs shelf, come back as
`{ "error": "..." }` with a `503` (not connected/configured), `404` (not found
upstream), `403` (missing scope), or `502` (upstream failure) status — documented
per endpoint below only where the status isn't one of those defaults.

## `GET /api/plays`

Cursor-paginated feed, newest first.

**Query params**

| Param | Description |
| --- | --- |
| `limit` | Page size, 1–100. Defaults to 30. |
| `before` | ISO-8601 instant; returns plays strictly before it. Omit for the first page. |
| `listener` | A `SpotifyAccount` id; restricts the feed to one listener. |

**Response**

```jsonc
{
  "plays": [
    {
      "id": 1,
      "played_at": "2026-08-28T12:00:00.000Z",
      "context_type": "playlist",       // or null
      "context_url": "spotify:playlist:...", // or null
      "listener": { "id": 1, "name": "...", "avatar_url": "...", "owner": true },
      "track": {
        "spotify_id": "...",
        "name": "...",
        "artists": "Artist A, Artist B",   // display string
        "album": "...",
        "album_spotify_id": "...",
        "album_image_url": "...",
        "spotify_url": "...",
        "duration_ms": 210000,
        "explicit": false,
        "artist_list": [                    // same credits, addressable, Spotify order
          { "id": "...", "name": "...", "url": "...", "image_url": "..." }
        ]
      }
    }
  ],
  "next_cursor": "2026-08-28T11:59:00.000Z" // or null when this is the last page
}
```

Paginate by passing the previous response's `next_cursor` back as `before`.

## `GET /api/status`

Who is on the feed, and whether owner-only actions should be offered.

**Response**

```jsonc
{
  "configured": true,   // Spotify app credentials are set
  "connected": true,     // at least one SpotifyAccount is linked
  "admin": false,        // caller already holds ADMIN_PASSWORD this session
  "listeners": [
    {
      "id": 1,
      "name": "...",
      "spotify_url": "https://open.spotify.com/user/...", // or null
      "avatar_url": "...",
      "owner": true,
      "last_synced_at": "2026-08-28T12:00:00Z", // or null, never synced
      "plays_count": 42
    }
  ]
}
```

`admin` is asked without challenging Basic auth, so a visitor is never shown a
password prompt just for loading the feed — see `AdminIdentified`.

## `GET /api/artists/:id/tracks`

An artist's top tracks (Spotify artist id). Cached 1 hour.

**Response**

```jsonc
{ "tracks": [ /* same track shape as api/plays, without album_spotify_id */ ] }
```

## `GET /api/albums/:id/tracks`

An album's tracks (Spotify album id). Cached 1 hour.

**Response**

```jsonc
{ "tracks": [ /* same track shape as api/plays, without album_spotify_id */ ] }
```

## `GET /api/albums/:id/discogs`

Whether a Spotify album has an already-resolved Discogs match.

**Response**

```jsonc
{ "url": "https://www.discogs.com/release/123456" } // or { "url": null }
```

## `GET /api/albums/releases`

Discogs releases that look like a given Spotify album, used to disambiguate
before matching. Never touches Spotify. Cached 2 minutes per `title`+`artist`.

**Query params**: `title`, `artist` — both required; returns `{ "releases": [] }`
if either is blank.

**Response**: `{ "releases": [ /* Discogs release payloads, shelf-defined shape */ ] }`

## `GET /api/playlists`

The owner's *public* playlists only. Cached 5 minutes.

**Response**

```jsonc
{
  "playlists": [
    {
      "id": "...",
      "name": "...",
      "description": "...",
      "image_url": "...",
      "spotify_url": "...",
      "tracks_count": 12
    }
  ]
}
```

`403` here means the owner's token is missing the `playlist-read-private` scope
and needs reconnecting.

## `GET /api/playlists/:id/tracks`

**Response**: `{ "tracks": [ /* same track shape as api/plays, without album_spotify_id */ ] }`

## `GET /api/top_items`

The owner's algorithmic top artists and tracks over the last ~6 months
(`GET /v1/me/top/{type}`, `medium_term`) — distinct from anything derived from
plays this app has synced. Cached 6 hours.

**Response**

```jsonc
{
  "artists": [
    { "id": "...", "name": "...", "image_url": "...", "spotify_url": "..." }
  ],
  "tracks": [ /* same track shape as api/plays, without album_spotify_id */ ]
}
```

`403` here means the owner's token is missing the `user-top-read` scope and
needs reconnecting.

## `GET /api/followed_artists`

Who the owner follows on Spotify (`GET /v1/me/following?type=artist`) — not
derived from anything synced locally. Cached 1 hour. Only the first page (up
to 50) is fetched; Spotify paginates this one by cursor rather than offset.

**Response**

```jsonc
{
  "artists": [
    { "id": "...", "name": "...", "image_url": "...", "spotify_url": "...", "followers": 1234 }
  ]
}
```

`403` here means the owner's token is missing the `user-follow-read` scope
and needs reconnecting.

## `GET /api/discogs/status`

Whether the sibling `discogs_shelf` app is configured and answering.

**Response**

```jsonc
{
  "configured": true,
  "url": "http://localhost:3001",
  "spotify_connected": true,
  "reachable": true,
  "username": "...",
  "collection_count": 500,
  "wantlist_count": 20,
  "last_sync": "2026-08-28T00:00:00Z"
}
```

When the shelf can't be reached, the last five fields collapse to
`{ "reachable": false, "error": "..." }`.

## `GET /api/discogs/releases`

The shelf's collection or wantlist, with cached Spotify match badges. Never
calls Spotify — only reports matches an earlier `show` visit already computed.
Cached 2 minutes per param set.

**Query params**: `list` (`collection` or `wantlist`, defaults to `collection`),
`q`, `genre`, `style`, `media`, `decade`, `sort`, `page`, `per_page` — passed
through to the shelf app.

**Response**

```jsonc
{
  "list": "collection",
  "items": [ /* shelf release payload, each with a "spotify" match summary or null */ ],
  "pagination": { /* shelf-defined */ },
  "facets": { /* shelf-defined */ },
  "sort": "..."
}
```

## `GET /api/discogs/releases/:id`

One release: its Discogs metadata, marketplace stats, and its Spotify match —
computed (and cached in `discogs_matches`) if not already known. This is the
one Discogs endpoint allowed to spend a Spotify request.

**Response**

```jsonc
{
  "release": {
    "discogs_id": 123456, "title": "...", "artist": "...", "artists": [ "..." ],
    "year": 1990, "country": "...", "label": "...", "catno": "...", "labels": [ "..." ],
    "genres": [ "..." ], "styles": [ "..." ], "format_summary": "...",
    "cover_url": "...", "thumb_url": "...", "discogs_url": "...",
    "released": "...", "notes": "..."
  },
  "marketplace": { /* shelf-defined, or null on failure */ },
  "spotify": {
    "album": "...", "market": "...",
    "track_count": 10, "playable_count": 8,
    "matched_at": "2026-08-28T00:00:00Z", // or null, never matched
    "error": null // or a human-readable reason matching failed
  },
  "tracks": [
    {
      "position": "A1",
      "title": "...",
      "duration": "3:45",
      "artists": "...", // or null
      "type": "track",
      "playable": true,
      "source": "...", // how the match was made, or null
      "track": { /* Spotify track payload */ } // or null, unmatched
    }
  ]
}
```

A release that can't be matched still renders — `spotify.error` explains why,
and every track's `playable` is `false`.
