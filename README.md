# Tocando ultimamente

Um site que mostra as últimas músicas tocadas na sua conta pessoal do Spotify e
deixa quem visita ouvir cada faixa sem sair da página.

- **Backend:** Ruby on Rails 8.1 (API + páginas)
- **Frontend:** React 19 via Vite (`vite_rails`)
- **Banco:** SQLite
- **Player:** embed oficial do Spotify

## Como funciona

O Spotify guarda apenas as **50 reproduções mais recentes** de uma conta. Por
isso o app não consulta a API a cada visita: um job roda a cada minuto, busca o
que é novo e grava no SQLite. O histórico do site cresce com o tempo, mesmo que
o Spotify já tenha descartado as faixas antigas.

```
Spotify API  ──(a cada 1 min)──▶  SyncRecentlyPlayedJob  ──▶  SQLite
                                                                │
                              React  ◀──  /api/plays  ◀─────────┘
```

Cada reprodução é identificada pelo instante em que tocou (`played_at`), que
tem índice único — sincronizar duas vezes a mesma janela não duplica nada. A
sincronização carrega os `played_at` da página inteira numa consulta só, em vez
de perguntar ao banco faixa por faixa: o poll comum traz 50 reproduções que já
estão gravadas e não importa nenhuma.

## Configuração

### 1. Crie um app no Spotify

1. Acesse <https://developer.spotify.com/dashboard> e clique em **Create app**.
2. Em **Redirect URIs**, adicione exatamente:
   `http://127.0.0.1:3000/spotify/callback`
   O Spotify exige o IP de loopback (`127.0.0.1`), não aceita `localhost`.
3. Em **APIs used**, marque **Web API**.
4. Copie o **Client ID** e o **Client Secret**.

O app pede dois escopos: `user-read-recently-played` (o histórico) e
`playlist-read-private` (a aba de playlists). Se você conectou a conta antes da
aba de playlists existir, refaça o `/spotify/connect` — sem o segundo escopo a
aba responde 403 e explica isso na tela.

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

## O site

A navegação tem quatro abas, e a aba escolhida vai para a URL (`?view=tracks`),
então o botão de voltar do navegador funciona:

- **Overview:** o feed recente, mais prateleiras de álbuns e artistas.
- **Tracks:** o histórico completo, agrupado por dia.
- **Artists:** a grade de artistas; clicar em um abre a página dele, com os
  destaques do seu histórico e as top tracks que a API do Spotify devolve.
- **Playlists:** suas playlists públicas e as faixas de cada uma.

Há ainda uma busca (que filtra só o que está na tela) e um filtro de período,
que é a lente global — a página do artista lê do conjunto já filtrado, e não do
que estiver digitado na busca.

O botão de **autoplay** no rodapé, ligado por padrão, faz o player seguir para a
próxima faixa sozinho; a preferência fica no `localStorage`. O próximo/anterior
anda pela lista de onde a faixa saiu: se você começou a tocar dentro de uma
página de artista, o player continua ali até você tocar outra coisa.

## Rotas

| Rota | Acesso | O que faz |
| --- | --- | --- |
| `GET /` | público | O app React |
| `GET /api/plays?limit=&before=` | público | Feed paginado por cursor |
| `GET /api/status` | público | Se a conta está conectada, total de reproduções |
| `GET /api/artists/:id/tracks` | público | Top tracks do artista (cache de 1h) |
| `GET /api/playlists` | público | Playlists públicas do dono (cache de 5min) |
| `GET /api/playlists/:id/tracks` | público | Faixas de uma playlist |
| `GET /spotify/connect` | dono | Inicia o OAuth |
| `GET /spotify/callback` | dono | Recebe o código e salva os tokens |
| `POST /spotify/sync` | dono | Sincroniza agora, sem esperar o job |
| `DELETE /spotify` | dono | Desvincula a conta |

As rotas públicas gastam a quota do Spotify do dono, então todas passam por um
`rate_limit` de 60 requisições por minuto: uma rajada levaria o app inteiro a um
429 na Spotify, o que também travaria a sincronização — e sincronização travada,
com só 50 reproduções guardadas do outro lado, é histórico perdido de vez. As
respostas do Spotify ficam em cache para não repetir a chamada a cada visita.

As rotas do dono são protegidas por HTTP Basic com a `ADMIN_PASSWORD` (qualquer
usuário, a senha é o que importa). Em desenvolvimento, sem a variável definida,
a proteção só é dispensada para requisições da própria máquina — um servidor
ligado em `0.0.0.0` ou exposto por túnel continua pedindo senha. Em produção ela
é obrigatória.

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
│   ├── api/                  # base (rate limit), plays, status, artists,
│   │                         #   playlists (JSON público)
│   ├── concerns/
│   │   └── admin_authenticated.rb
│   └── spotify/              # sessions (OAuth), syncs
├── frontend/                 # React
│   ├── components/           # App, Sidebar, TopBar, Hero, Shelf, ArtistView,
│   │                         #   PlaylistView, PlayFeed, PlayRow, PlayerBar,
│   │                         #   SetupNotice, icons
│   ├── hooks/                # usePlays, useSpotifyEmbed
│   ├── images/               # logo e wordmark
│   ├── lib/                  # api.js, derive.js, format.js
│   └── styles/
├── jobs/
│   └── sync_recently_played_job.rb
├── models/                   # Track, Play, Artist, TrackArtist, SpotifyAccount
└── services/spotify/         # client, authorization, recently_played_sync,
                              #   artist_backfill
```

`Track` guarda a música; `Play` guarda cada vez que ela tocou. A mesma faixa
ouvida cinco vezes vira um `Track` e cinco `Play`. `Artist` existe à parte
porque o payload de reprodução não traz a foto do artista — o `ArtistBackfill`
busca essas imagens depois, quando aparece gente nova.

## Qualidade

```bash
bin/rails test     # testes
bin/rubocop        # estilo
```

Os testes cobrem a normalização do payload do Spotify, a idempotência da
sincronização, a criptografia dos tokens, a paginação por cursor, as recusas do
fluxo OAuth, a proteção da rota de sync e os endpoints de artistas e playlists.
O ambiente de teste usa chaves de criptografia fixas, então nem os testes locais
nem a CI precisam da `master.key`.

O hook em `.githooks/pre-commit` roda RuboCop e os testes antes de cada commit.
Para ativá-lo num clone novo:

```bash
git config core.hooksPath .githooks
```

A CI (`.github/workflows/ci.yml`) roda o mesmo, mais Brakeman, bundler-audit e o
build do frontend. Há também uma skill de review em
`.claude/skills/code-reviewer/`, usada pelo Claude Code.

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
- defina `APP_HOST` com o domínio canônico, que liga a proteção contra DNS
  rebinding (`/up` fica de fora, porque load balancer chega por IP).

A Content Security Policy já vem ativa em
`config/initializers/content_security_policy.rb`: libera `open.spotify.com` em
`script-src`/`frame-src`, imagens por HTTPS (as capas vêm de CDNs que o Spotify
troca sem aviso) e nada de `object-src` ou de ser embutido em outra página.

## Privacidade

O site publica o que você ouve. Só isso é exposto: nome da faixa, artistas,
capa e horário. Tokens ficam criptografados no banco (Active Record Encryption)
e nunca chegam ao frontend. Para parar de publicar, `DELETE /spotify` desvincula
a conta — os registros já gravados continuam no banco até você apagá-los.
