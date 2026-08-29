import { useCallback, useEffect, useRef, useState } from "react"
import { fetchPlays } from "../lib/api"

const REFRESH_INTERVAL = 60_000
// loadAll pages through the *entire* history in one go — at the feed's own
// page size (30) a real history of a few hundred plays is 15-20 requests
// back to back, enough on its own to trip Api::BaseController's 60/min rate
// limit after a couple of reloads. The API's own ceiling (Api::PlaysController
// ::MAX_LIMIT) cuts that to a handful of requests for the same data.
const LOAD_ALL_PAGE_SIZE = 100

// Owns the feed: first page, cursor pagination, and a quiet poll that
// prepends whatever the background sync has picked up since.
export function usePlays({ pageSize = 30, listener = null } = {}) {
  const [plays, setPlays] = useState([])
  const [cursor, setCursor] = useState(null)
  const [status, setStatus] = useState("loading") // loading | ready | error
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState(null)

  // Kept in a ref so the polling effect never has to re-subscribe.
  const newestPlayedAt = useRef(null)

  const loadFirstPage = useCallback(
    async (signal) => {
      try {
        const data = await fetchPlays({ limit: pageSize, listener, signal })
        setPlays(data.plays)
        setCursor(data.next_cursor)
        newestPlayedAt.current = data.plays[0]?.played_at ?? null
        setStatus("ready")
      } catch (cause) {
        if (signal?.aborted) return
        setError(cause)
        setStatus("error")
      }
    },
    [pageSize, listener]
  )

  useEffect(() => {
    // Switching listener is a different feed, not more of the same one: reset
    // so the previous person's rows cannot linger behind the new first page.
    setStatus("loading")
    setPlays([])
    setCursor(null)
    newestPlayedAt.current = null

    const controller = new AbortController()
    loadFirstPage(controller.signal)
    return () => controller.abort()
  }, [loadFirstPage])

  const loadMore = useCallback(async () => {
    if (!cursor || loadingMore) return

    setLoadingMore(true)
    try {
      const data = await fetchPlays({ before: cursor, limit: pageSize, listener })
      setPlays((current) => [...current, ...data.plays])
      setCursor(data.next_cursor)
    } catch (cause) {
      setError(cause)
    } finally {
      setLoadingMore(false)
    }
  }, [cursor, loadingMore, pageSize, listener])

  const loadAll = useCallback(async () => {
    if (!cursor || loadingMore) return

    setLoadingMore(true)
    let nextCursor = cursor

    try {
      while (nextCursor) {
        const data = await fetchPlays({ before: nextCursor, limit: LOAD_ALL_PAGE_SIZE, listener })
        setPlays((current) => [...current, ...data.plays])
        nextCursor = data.next_cursor
        setCursor(nextCursor)
      }
    } catch (cause) {
      setError(cause)
    } finally {
      setLoadingMore(false)
    }
  }, [cursor, loadingMore, listener])

  // Poll for fresher plays without disturbing what's already on screen.
  useEffect(() => {
    const timer = setInterval(async () => {
      if (document.hidden) return

      try {
        const data = await fetchPlays({ limit: pageSize, listener })
        const boundary = newestPlayedAt.current
        const fresh = boundary ? data.plays.filter((play) => play.played_at > boundary) : data.plays
        if (fresh.length === 0) return

        newestPlayedAt.current = fresh[0].played_at
        setPlays((current) => [...fresh, ...current])
      } catch {
        // A failed poll is harmless: the next one will catch up.
      }
    }, REFRESH_INTERVAL)

    return () => clearInterval(timer)
  }, [pageSize, listener])

  return { plays, status, error, loadMore, loadAll, loadingMore, hasMore: Boolean(cursor) }
}
