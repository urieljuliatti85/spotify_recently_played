// timeOfDay/dayLabel format an ISO string through the local timezone, so
// pinning it is what keeps those tests deterministic across machines and CI.
process.env.TZ = "UTC"
