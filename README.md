# element

Imagem Docker **white-label do [Element Web](https://github.com/element-hq/element-web)**
com um branding genérico criado (paleta e layout do site
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

Só **quatro** coisas são configuráveis — tudo o mais (tema, CSS, ícones, fundo) é criado:

| Variável | Default | Descrição |
|---|---|---|
| `ELEMENT_BASE_URL` | `https://matrix.example.com` | `base_url` do homeserver Matrix |
| `ELEMENT_SERVER_NAME` | `example.com` | `server_name` (a identidade `@user:server_name`) |
| `ELEMENT_BRAND` | `Chat` | nome exibido no título, no `config.json` e na página de boas-vindas |
| `ELEMENT_TAGLINE` | `Converse em tempo real…` | frase de destaque da tela de boas-vindas (ver abaixo) |

### `ELEMENT_TAGLINE` — a frase da tela de boas-vindas

Aceita **HTML simples** (`<strong>`, `<em>`, `<br>`, `<a>`): o Element sanitiza a página de
boas-vindas ao renderizar, então tags perigosas (`<script>` etc.) são descartadas.

```bash
-e ELEMENT_TAGLINE='Fale com o <strong>síndico</strong> e com a portaria — <em>sem grupo de WhatsApp</em>.'
```

Passar **vazio esconde a frase** (o parágrafo some, sem deixar buraco no card):

```bash
-e ELEMENT_TAGLINE=''
```

## O que é criado vs. configurável

| Criado (fixo na imagem) | Configurável (env, runtime) |
|---|---|
| Tema escuro (paleta marcelomatos.dev), `custom.css`, logos, favicon/ícones PWA | `ELEMENT_BASE_URL` |
| `login-bg.jpg`, template do `welcome.html`, injeção do CSS no `index.html` | `ELEMENT_SERVER_NAME` |
| Cores do tema, gradientes de login/botões | `ELEMENT_BRAND` (nome da marca) |
| Layout da página de boas-vindas (logo, título, botão) | `ELEMENT_TAGLINE` (frase de destaque) |

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
  base["vectorim/element-web:v1.12.23<br/>(nginx :8080)"]
  brand["branding criado<br/>(logo, tema, css, login-bg,<br/>favicon, ícones PWA)"]
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
  -e ELEMENT_TAGLINE='Atendimento <strong>seguro</strong> — direto do navegador.' \
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

## Correções aplicadas sobre o Element base

### Mensagens de voz Opus/Ogg (FluffyChat) não tocavam

Mensagens de voz gravadas no **FluffyChat** renderizavam waveform e duração, mas o play não
funcionava — no Firefox o player errava, no Chrome ele simplesmente nunca ficava pronto.

**A causa raiz não está no Element nem no codec:** o FluffyChat grava um Ogg cuja **última
página não tem a flag `EOS`** (end-of-stream). O fluxo Opus está intacto. O efeito:

| | `decodeAudioData` nativo | `decodeOgg` (fallback WASM do Element) |
|---|---|---|
| **Firefox** | ❌ `EncodingError` | ❌ o worker não emite nada |
| **Chrome** | ✅ decodifica (demuxer tolerante) | ❌ o worker não emite nada |

Como o `decodeOgg` do Element **não tem caminho de `reject`** (*"no reject because the workers
don't seem to have a fail path"*, diz o próprio comentário), quando ele é acionado o `await`
fica pendurado para sempre: `prepare()` nunca termina, o player nunca fica pronto e **nenhum
erro é logado**.

A imagem injeta [`branding/opus-fix.js`](branding/opus-fix.js) no `index.html` (build-time),
que envolve `BaseAudioContext.prototype.decodeAudioData` e:

1. **Entrega uma cópia** do buffer ao decodificador nativo — a Web Audio API destaca
   (neutraliza) o buffer de entrada **mesmo quando a decodificação falha**, e sem a cópia o
   fallback do Element recebia um buffer destacado e lançava `TypeError: detached ArrayBuffer`.
2. **Repara o Ogg** quando o nativo falha: liga o bit `EOS` na última página, recalcula o
   CRC-32 dela e tenta decodificar de novo. Funcionando, o Element **nem chega** no `decodeOgg`
   que trava. Se não houver reparo possível, o erro original é propagado.

Ligar só o EOS (sem tocar num byte de Opus) faz o arquivo decodificar no Firefox, no Chrome e
no worker do Element — verificado nos dois navegadores contra um arquivo real.

- **Não exige buildar o Element do fonte** (o bundle oficial é minificado).
- **Inofensivo** para arquivos sãos: só age quando o decode nativo falha e o Ogg está sem EOS.

Bugs **abertos upstream**: [element-web#32034](https://github.com/element-hq/element-web/issues/32034)
(o `Playback.ts` é idêntico em `v1.12.21`…`v1.12.23` e no `develop` — subir a tag base **não**
corrige) e, a montante de tudo, o encoder do FluffyChat que não finaliza o stream Ogg.
Verificação repetível: cole [`specs/opus-fix.verify.js`](specs/opus-fix.verify.js) no console do navegador.


### Interface em inglês / chaves de i18n cruas em pt-BR

As traduções do Element vêm do **Localazy** e ficam atrás das releases. No `v1.12.23` o
`pt_BR` estava com **256 chaves faltando (6,9%)** — os filtros da lista de salas apareciam
em inglês (`Unreads`, `People`, `Rooms`) e o popup de anúncio das Seções chegava a mostrar
a **chave crua** (`release_announcement|room_list_section_title`), porque o fallback do
Element não resolve essas chaves.

Não é configuração nossa: reproduz na imagem base crua, e o `pt_BR.json` do upstream não
tem essas chaves nem no `develop`.

A imagem corrige em build-time (com o `jq` que já existe na base):

1. Aplica `branding/i18n-ptbr-extra.json` — as **256 chaves traduzidas para pt-BR**, seguindo
   a terminologia que o próprio `pt_BR` já usa (`Sala`, `Pessoas`, `Favoritos`, `Baixa prioridade`).
2. Completa o que sobrar a partir do `en_EN` (o que um fallback funcional faria), para **nunca
   restar chave crua**.

`jq -s '.[0] * .[1] * .[2]'` faz merge recursivo com o operando da direita vencendo
(`en` → `pt_BR` do upstream → nossas). **Não sobrescreve tradução existente**: as 256 são
exatamente as que faltavam, verificado no build. Resultado: `pt_BR` com as mesmas 3684 chaves
do `en_EN`.

## Atualizar a versão do Element base

Trocar a tag no `FROM` do `Dockerfile` (`vectorim/element-web:vX.Y.Z`) e rebuildar.
Confira que a base nova ainda usa `#76CFA6` no `manifest.json` (o `sed` do tema falha em
silêncio se a cor mudar) e rode `specs/opus-fix.verify.js` no console: se o upstream tiver
corrigido o fallback, o shim continua inofensivo e pode ser removido.

## CI/CD (GitHub Actions → GHCR → Portainer)

A imagem é versionada em **SemVer** e publicada no **GHCR** (`ghcr.io/marcelofmatos/element`).

| Workflow | Gatilho | Faz |
|---|---|---|
| `release-and-build.yml` | manual (`workflow_dispatch`, patch/minor/major) | calcula SemVer, cria tag + release, builda e publica no GHCR (full/minor/major/latest) |
| `docker-image.yml` | push em `homolog`/`prod`, release, manual | builda/publica no GHCR por branch + dispara webhook de deploy |
| `deploy.yml` | após "Release and build" em `main` | dispara webhooks Portainer (HMG → PRD) |
| `docker-set-tag.yml` | manual | promove (re-aponta) uma docker tag para uma release |

**Secrets/variáveis** (Settings → Secrets and variables → Actions):
- `PORTAINER_DEPLOY_HMG_WEBHOOK_URL` / `PORTAINER_DEPLOY_PRD_WEBHOOK_URL` — webhooks do stack no Portainer
- (opcional) `WEBHOOK_DEPLOY_MAIN` / `WEBHOOK_DEPLOY_HOMOLOG` — usados pelo `docker-image.yml`
- Variável `USE_ENVIRONMENTS` (`true`/`false`) — liga/desliga os GitHub Environments no `deploy.yml`

> O `GITHUB_TOKEN` já tem `packages: write` para publicar no GHCR. Após o primeiro
> publish, deixe o **pacote GHCR público** (Packages → element → Package settings →
> Change visibility) para que a imagem seja _pullable_ anonimamente (ex.: pela stack do Portainer).

## Licença

O branding deste repositório é livre para uso. O **Element Web** empacotado é
distribuído sob **AGPL-3.0-only** — veja o
[projeto upstream](https://github.com/element-hq/element-web).
