export default function SetupNotice({ status, connectPath }) {
  if (!status) return null

  if (!status.configured) {
    return (
      <div className="notice notice--warning">
        <h2>Faltam as credenciais do Spotify</h2>
        <p>
          Defina <code>SPOTIFY_CLIENT_ID</code> e <code>SPOTIFY_CLIENT_SECRET</code> no arquivo{" "}
          <code>.env</code> e reinicie o servidor. O passo a passo está no <code>README.md</code>.
        </p>
      </div>
    )
  }

  return (
    <div className="notice">
      <h2>Conecte sua conta do Spotify</h2>
      <p>Autorize uma vez e o app passa a guardar cada música tocada automaticamente.</p>
      <a className="notice__cta" href={connectPath}>
        Conectar Spotify
      </a>
    </div>
  )
}
