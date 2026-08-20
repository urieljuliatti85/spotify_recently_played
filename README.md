# Tocando ultimamente

Um site que mostra as últimas músicas tocadas na sua conta pessoal do Spotify e
deixa quem visita ouvir cada faixa sem sair da página.

- **Backend:** Ruby on Rails 8.1 (API + páginas)
- **Frontend:** React 19 via Vite (`vite_rails`)
- **Banco:** SQLite
- **Player:** embed oficial do Spotify

## Como funciona

O Spotify guarda apenas as **50 reproduções mais recentes** de uma conta. Por
isso o app não consulta a API a cada visita: um job roda a cada 5 minutos,
busca o que é novo e grava no SQLite. O histórico do site cresce com o tempo,
mesmo que o Spotify já tenha descartado as faixas antigas.

```
Spotify API  ──(a cada 5 min)──▶  SyncRecentlyPlayedJob  ──▶  SQLite
                                                                │
                              React  ◀──  /api/plays  ◀─────────┘
```

Cada reprodução é identificada pelo instante em que tocou (`played_at`), que
tem índice único — sincronizar duas vezes a mesma janela não duplica nada.

## Configuração

### 1. Crie um app no Spotify

1. Acesse <https://developer.spotify.com/dashboard> e clique em **Create app**.
2. Em **Redirect URIs**, adicione exatamente:
   `http://127.0.0.1:3000/spotify/callback`
   O Spotify exige o IP de loopback (`127.0.0.1`), não aceita `localhost`.
3. Em **APIs used**, marque **Web API**.
4. Copie o **Client ID** e o **Client Secret**.

### 2. Configure o projeto

```bash
cp .env.example .env
```

Preencha o `.env`:

```
SPOTIFY_CLIENT_ID=seu_client_id
SPOTIFY_CLIENT_SECRET=seu_client_secret
SPOTIFY_REDIRECT_URI=http://127.0.0.1:3000/spotify/callback
ADMIN_PASSWORD=uma_senha_qualquer
```

O `.env` já está no `.gitignore`. As credenciais também podem ficar em
`config/credentials.yml.enc`, sob a chave `spotify:` — o `.env` tem prioridade.

### 3. Suba a aplicação

Requisitos: Ruby 3.3+, Node 20+ e SQLite 3.8+.


```bash
bin/setup     # instala gems e pacotes npm, cria o .env, prepara o banco e sobe tudo
```

Nas vezes seguintes, `bin/dev` sozinho já basta.

`bin/dev` usa o [foreman](https://github.com/ddollar/foreman) para tocar os três
processos do `Procfile.dev`; se ele não estiver instalado, o script instala na
primeira execução. O Rails fica fixado na porta 3000 (o foreman usaria 5000 por
padrão, e o Redirect URI precisa bater exatamente).

Abra <http://127.0.0.1:3000> e clique em **Connect Spotify** (ou vá direto em
`/spotify/connect`). Você autoriza uma vez; o refresh token fica salvo,
criptografado, e as sincronizações seguintes acontecem sozinhas.

> Use `127.0.0.1:3000`, e não `localhost:3000` — o endereço precisa bater com o
> Redirect URI cadastrado.

## Rotas

| Rota | Acesso | O que faz |
| --- | --- | --- |
| `GET /` | público | O app React |
| `GET /api/plays?limit=&before=` | público | Feed paginado por cursor |
| `GET /api/status` | público | Se a conta está conectada, total de reproduções |
| `GET /spotify/connect` | dono | Inicia o OAuth |
| `GET /spotify/callback` | dono | Recebe o código e salva os tokens |
| `POST /spotify/sync` | dono | Sincroniza agora, sem esperar o job |
| `DELETE /spotify` | dono | Desvincula a conta |

As rotas do dono são protegidas por HTTP Basic com a `ADMIN_PASSWORD` (qualquer
usuário, a senha é o que importa). Em desenvolvimento, se a variável não estiver
definida, a proteção é dispensada; em produção ela é obrigatória.

Sincronizar manualmente:

```bash
bin/rails spotify:sync
# ou
curl -u owner:$ADMIN_PASSWORD -X POST http://127.0.0.1:3000/spotify/sync
```

## O player

Cada faixa abre no player fixo no rodapé, usando o
[iframe embed do Spotify](https://developer.spotify.com/documentation/embeds).
Um único player fica vivo na página e troca de faixa a cada clique.

O que a pessoa ouve depende de quem ela é:

- **Sem login no Spotify:** prévia de 30 segundos.
- **Logada no Spotify:** a faixa inteira.

Não é preciso Premium nem login no seu site. O campo `preview_url` da API foi
descontinuado pelo Spotify para apps novos, então hospedar o áudio por conta
própria não é uma alternativa viável — o embed é o caminho suportado.

Se o script do Spotify não carregar (bloqueador de anúncios, por exemplo), o app
cai para um `<iframe>` simples, que continua tocando — só exige um clique a mais
no botão de play.

## Estrutura

```
app/
├── controllers/
│   ├── api/                  # plays#index, status#show (JSON público)
│   ├── concerns/
│   │   └── admin_authenticated.rb
│   └── spotify/              # sessions (OAuth), syncs
├── frontend/                 # React
│   ├── components/           # App, Sidebar, TopBar, Hero, Shelf, ArtistView,
│   │                         #   PlayFeed, PlayRow, PlayerBar, SetupNotice, icons
│   ├── hooks/                # usePlays, useSpotifyEmbed
│   ├── images/               # logo e wordmark
│   ├── lib/                  # api.js, derive.js, format.js
│   └── styles/
├── jobs/
│   └── sync_recently_played_job.rb
├── models/                   # Track, Play, SpotifyAccount
└── services/spotify/         # client, authorization, recently_played_sync
```

`Track` guarda a música; `Play` guarda cada vez que ela tocou. A mesma faixa
ouvida cinco vezes vira um `Track` e cinco `Play`.

## Testes

```bash
bin/rails test
```

Cobrem a normalização do payload do Spotify, a idempotência da sincronização, a
criptografia dos tokens, a paginação por cursor e as recusas do fluxo OAuth.

## Deploy

O `config/recurring.yml` já agenda a sincronização em produção, então basta ter
o Solid Queue rodando (`bin/jobs`) junto com o servidor web. Como o banco é
SQLite, o disco precisa ser persistente.

Antes de expor o site publicamente:

- defina `ADMIN_PASSWORD` (sem ela, as rotas do dono se recusam a funcionar);
- gere `RAILS_MASTER_KEY` a partir de `config/master.key` — é ela que decifra os
  tokens do Spotify;
- cadastre o Redirect URI de produção (HTTPS) no dashboard do Spotify e ajuste
  `SPOTIFY_REDIRECT_URI`;
- considere ativar uma Content Security Policy em
  `config/initializers/content_security_policy.rb`, liberando `open.spotify.com`
  em `script-src`/`frame-src` e `i.scdn.co` em `img-src`.

## Privacidade

O site publica o que você ouve. Só isso é exposto: nome da faixa, artistas,
capa e horário. Tokens ficam criptografados no banco (Active Record Encryption)
e nunca chegam ao frontend. Para parar de publicar, `DELETE /spotify` desvincula
a conta — os registros já gravados continuam no banco até você apagá-los.
