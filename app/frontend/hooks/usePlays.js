import { useCallback, useEffect, useRef, useState } from "react"
import { fetchPlays } from "../lib/api"

const REFRESH_INTERVAL = 60_000

// Owns the feed: first page, cursor pagination, and a quiet poll that
// prepends whatever the background sync has picked up since.
export function usePlays({ pageSize = 30 } = {}) {
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
        const data = await fetchPlays({ limit: pageSize, signal })
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
    [pageSize]
  )

  useEffect(() => {
    const controller = new AbortController()
    loadFirstPage(controller.signal)
    return () => controller.abort()
  }, [loadFirstPage])

  const loadMore = useCallback(async () => {
    if (!cursor || loadingMore) return

    setLoadingMore(true)
    try {
      const data = await fetchPlays({ before: cursor, limit: pageSize })
      setPlays((current) => [...current, ...data.plays])
      setCursor(data.next_cursor)
    } catch (cause) {
      setError(cause)
    } finally {
      setLoadingMore(false)
    }
  }, [cursor, loadingMore, pageSize])

  const loadAll = useCallback(async () => {
    if (!cursor || loadingMore) return

    setLoadingMore(true)
    let nextCursor = cursor

    try {
      while (nextCursor) {
        const data = await fetchPlays({ before: nextCursor, limit: pageSize })
        setPlays((current) => [...current, ...data.plays])
        nextCursor = data.next_cursor
        setCursor(nextCursor)
      }
    } catch (cause) {
      setError(cause)
    } finally {
      setLoadingMore(false)
    }
  }, [cursor, loadingMore, pageSize])

  // Poll for fresher plays without disturbing what's already on screen.
  useEffect(() => {
    const timer = setInterval(async () => {
      if (document.hidden) return

      try {
        const data = await fetchPlays({ limit: pageSize })
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
  }, [pageSize])

  return { plays, status, error, loadMore, loadAll, loadingMore, hasMore: Boolean(cursor) }
}
