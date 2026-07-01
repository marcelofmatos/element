# element

Imagem Docker **white-label do [Element Web](https://github.com/element-hq/element-web)**
com um branding genérico assado (paleta e layout do site
[marcelomatos.dev](https://marcelomatos.dev) — tema escuro violeta → magenta → ciano).

Serve para **demonstrar o chat Matrix a novos clientes**: uma tela de login e de
boas-vindas já bonitas e neutras, prontas para apontar para qualquer homeserver e
exibir o nome da marca do cliente — **sem rebuild**, só variáveis de ambiente.

Imagem autocontida (o branding vai dentro dela), necessária para deploy em
**Swarm/cloud** (Portainer), onde bind mounts relativos não funcionam.

| | Preview |
|---|---|
| **Login** | painel com gradiente violeta → ciano, balão de chat branco, fundo escuro com _glows_ radiais |
| **Boas-vindas** | card com o nome da marca em gradiente, CTA "Entrar", ícone do app |

## Configuração (runtime, via env)

Só **três** coisas são configuráveis — tudo o mais (tema, CSS, ícones, fundo) é assado:

| Variável | Default | Descrição |
|---|---|---|
| `ELEMENT_BASE_URL` | `https://matrix.example.com` | `base_url` do homeserver Matrix |
| `ELEMENT_SERVER_NAME` | `example.com` | `server_name` (a identidade `@user:server_name`) |
| `ELEMENT_BRAND` | `Chat` | nome exibido no título, no `config.json` e na página de boas-vindas |

## O que é assado vs. configurável

| Assado (fixo na imagem) | Configurável (env, runtime) |
|---|---|
| Tema escuro (paleta marcelomatos.dev), `custom.css`, logos, favicon/ícones PWA | `ELEMENT_BASE_URL` |
| `login-bg.jpg`, template do `welcome.html`, injeção do CSS no `index.html` | `ELEMENT_SERVER_NAME` |
| Cores do tema, gradientes de login/botões | `ELEMENT_BRAND` (nome da marca) |

## Paleta (origem: marcelomatos.dev)

| Papel | Cor |
|---|---|
| Fundo | `#070611` |
| Texto | `#f3f0ff` · secundário `#a99fce` |
| Accent (violeta) | `#7c3aed` |
| Primário/magenta | `#d946ef` |
| Ciano | `#06b6d4` |
| Gradiente de login | violeta → ciano · Botões | violeta → magenta |

## Arquitetura

```mermaid
flowchart LR
  base["vectorim/element-web:v1.12.21<br/>(nginx :8080)"]
  brand["branding assado<br/>(logo, tema, css, login-bg,<br/>favicon, ícones PWA)"]
  tmpl["config.json.template +<br/>welcome.html.template"]
  entry["docker-entrypoint.sh"]

  subgraph img["Imagem element (build-time)"]
    base --> entry
    brand --> entry
    tmpl --> entry
  end

  env["env em runtime<br/>ELEMENT_BASE_URL<br/>ELEMENT_SERVER_NAME<br/>ELEMENT_BRAND"] --> entry
  entry -->|gera + serve| user["Navegador do cliente<br/>(login + welcome)"]
```

## Fluxo do container (start → serve)

```mermaid
sequenceDiagram
  participant C as Container start
  participant S as docker-entrypoint.sh
  participant N as nginx

  C->>S: ENTRYPOINT
  S->>S: defaults p/ ELEMENT_BASE_URL, ELEMENT_SERVER_NAME, ELEMENT_BRAND
  S->>S: envsubst → /app/config.json (homeserver + brand + tema)
  S->>S: envsubst → /app/branding/welcome.html (brand)
  S->>N: exec nginx (daemon off, escuta 8080)
  N-->>N: serve /config.json e /branding/* de /app
```

> Roda como root para gravar `/app/config.json` e `/app/branding/welcome.html`. Não usa
> a cadeia `/docker-entrypoint.d/` da base (que só roda como root e seria frágil); por
> isso o healthcheck é redefinido explicitamente em `127.0.0.1:8080` (IPv4).

## Build / run local

```bash
docker build -t element:dev .

# nginx do Element escuta na 8080 dentro do container
docker run --rm -p 8080:8080 \
  -e ELEMENT_BASE_URL=https://matrix.example.com \
  -e ELEMENT_SERVER_NAME=example.com \
  -e ELEMENT_BRAND="Acme Chat" \
  element:dev
# abra http://localhost:8080  (config em http://localhost:8080/config.json)
```

## Trocar de marca / homeserver (sem rebuild)

```bash
docker run --rm -p 8080:8080 \
  -e ELEMENT_BASE_URL=https://matrix.suaempresa.com \
  -e ELEMENT_SERVER_NAME=suaempresa.com \
  -e ELEMENT_BRAND="Sua Empresa" \
  element:dev
```

## Personalizar o branding (rebuild)

O visual fica em [`branding/`](branding/) e nos templates:

- `branding/custom.css` — gradiente do painel de login e botões
- `branding/logo-mark.svg` — marca mostrada no painel de login
- `branding/logo.png`, `branding/vector-icons/*`, `branding/favicon.ico` — ícones (app / PWA / favicon)
- `branding/login-bg.jpg` — fundo da tela de login
- `welcome.html.template` — página de boas-vindas (usa `${ELEMENT_BRAND}`)
- `config.json.template` — cores do tema custom "Dark"

Depois é só `docker build` de novo.

## Atualizar a versão do Element base

Trocar a tag no `FROM` do `Dockerfile` (`vectorim/element-web:vX.Y.Z`) e rebuildar.

## Licença

O branding deste repositório é livre para uso. O **Element Web** empacotado é
distribuído sob **AGPL-3.0-only** — veja o
[projeto upstream](https://github.com/element-hq/element-web).
