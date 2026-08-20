export default function SetupNotice({ status, connectPath }) {
  if (!status) return null

  if (!status.configured) {
    return (
      <div className="notice notice--warning">
        <h2>Spotify credentials are missing</h2>
        <p>
          Set <code>SPOTIFY_CLIENT_ID</code> and <code>SPOTIFY_CLIENT_SECRET</code> in the{" "}
          <code>.env</code> file and restart the server. The walkthrough is in <code>README.md</code>.
        </p>
      </div>
    )
  }

  return (
    <div className="notice">
      <h2>Connect your Spotify account</h2>
      <p>Authorize once and the app starts saving every track you play, automatically.</p>
      <a className="notice__cta" href={connectPath}>
        Connect Spotify
      </a>
    </div>
  )
}
