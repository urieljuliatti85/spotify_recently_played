import { describe, expect, test } from "vitest"
import { dayKey, dayLabel, duration, groupByDay, relativeTime, timeOfDay } from "./format"

describe("timeOfDay", () => {
  test("formats an ISO string as a local clock time", () => {
    expect(timeOfDay("2024-01-15T14:30:00.000Z")).toBe("02:30 PM")
  })
})

describe("relativeTime", () => {
  const now = new Date("2024-01-15T12:00:00.000Z").getTime()

  test("collapses anything under a minute to 'just now'", () => {
    expect(relativeTime(new Date(now - 30_000).toISOString(), now)).toBe("just now")
  })

  test("counts in minutes under an hour", () => {
    expect(relativeTime(new Date(now - 5 * 60_000).toISOString(), now)).toBe("5 minutes ago")
  })

  test("counts in hours under a day", () => {
    expect(relativeTime(new Date(now - 3 * 3_600_000).toISOString(), now)).toBe("3 hours ago")
  })

  test("counts in days under a week", () => {
    expect(relativeTime(new Date(now - 2 * 86_400_000).toISOString(), now)).toBe("2 days ago")
  })

  test("also works forward in time", () => {
    expect(relativeTime(new Date(now + 5 * 60_000).toISOString(), now)).toBe("in 5 minutes")
  })

  // The day heading already carries the date at that distance, so a relative
  // label would only repeat it.
  test("returns null at a week or older", () => {
    expect(relativeTime(new Date(now - 8 * 86_400_000).toISOString(), now)).toBeNull()
  })
})

describe("dayKey", () => {
  test("is the same for two instants on the same local day", () => {
    expect(dayKey("2024-01-15T00:00:01.000Z")).toBe(dayKey("2024-01-15T23:59:00.000Z"))
  })

  test("differs across a day boundary", () => {
    expect(dayKey("2024-01-15T23:59:00.000Z")).not.toBe(dayKey("2024-01-16T00:00:01.000Z"))
  })
})

describe("dayLabel", () => {
  const now = new Date("2024-06-15T12:00:00.000Z")

  test("labels the current day as Today", () => {
    expect(dayLabel("2024-06-15T09:00:00.000Z", now)).toBe("Today")
  })

  test("labels the previous day as Yesterday", () => {
    expect(dayLabel("2024-06-14T09:00:00.000Z", now)).toBe("Yesterday")
  })

  test("writes out day and month for an older date in the same year", () => {
    expect(dayLabel("2024-01-02T09:00:00.000Z", now)).toBe("Tuesday, January 2")
  })

  test("includes the year once it is not the current one", () => {
    expect(dayLabel("2023-01-02T09:00:00.000Z", now)).toBe("January 2, 2023")
  })
})

describe("duration", () => {
  test("renders minutes:seconds, zero-padded", () => {
    expect(duration(65_000)).toBe("1:05")
  })

  test("rounds to the nearest second", () => {
    expect(duration(59_600)).toBe("1:00")
  })

  // `!ms` is true for both — a track with no known length and one that is
  // reported as exactly zero read the same way: nothing worth showing.
  test("is null for zero or missing duration", () => {
    expect(duration(0)).toBeNull()
    expect(duration(null)).toBeNull()
    expect(duration(undefined)).toBeNull()
  })
})

describe("groupByDay", () => {
  test("keeps newest-first plays in one group per day", () => {
    const plays = [
      { played_at: "2024-06-15T20:00:00.000Z" },
      { played_at: "2024-06-15T09:00:00.000Z" },
      { played_at: "2024-06-14T09:00:00.000Z" },
    ]

    const groups = groupByDay(plays)

    expect(groups).toHaveLength(2)
    expect(groups[0].plays).toHaveLength(2)
    expect(groups[1].plays).toHaveLength(1)
  })

  test("returns no groups for no plays", () => {
    expect(groupByDay([])).toEqual([])
  })
})
