# Element Web com branding white-label criado (paleta do marcelomatos.dev).
# Imagem generica para demonstrar o chat a novos clientes: o homeserver e o nome
# da marca sao injetados em runtime via ELEMENT_BASE_URL / ELEMENT_SERVER_NAME / ELEMENT_BRAND.
FROM vectorim/element-web:v1.12.23

# A base roda como usuario nginx e /app e root; os passos de build (sed/COPY) e o
# entrypoint (que grava /app/config.json) precisam de root. nginx escuta 8080.
USER root

# nginx escuta 8080 (default.conf estatico da base), so em IPv4 — o script da base que
# adiciona o `listen [::]:8080` (IPv6) faz parte da cadeia /docker-entrypoint.d/ que o
# nosso entrypoint ignora. O HEALTHCHECK da base usa `localhost` + `$ELEMENT_WEB_PORT`
# (var setada pelo entrypoint da base, que tambem ignoramos): localhost resolve p/ ::1
# (IPv6) e a porta fica vazia → o check nunca passa e a task trava em "starting".
# Redefinimos um healthcheck explicito em 127.0.0.1:8080 (IPv4), autocontido.
ENV ELEMENT_WEB_PORT=8080
HEALTHCHECK --start-period=10s --interval=30s --timeout=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/config.json || exit 1

# Branding criado: servido em /branding/* (nginx root = /usr/share/nginx/html -> /app)
COPY branding/ /app/branding/
COPY branding/favicon.ico /app/favicon.ico

# Favicon/icones PWA: o Element referencia vector-icons/<size>(.<hash>).png no index.html
# e no manifest.json — NAO o /favicon.ico. Sobrescreve esses icones (variantes com e sem
# hash) pelo icone da marca e ajusta o theme_color do manifest para o fundo escuro (#070611).
RUN set -e; \
    for s in 24 120 144 152 180 512 1024; do \
      for f in /app/vector-icons/${s}.png /app/vector-icons/${s}.*.png; do \
        [ -f "$f" ] && cp "/app/branding/vector-icons/${s}.png" "$f"; \
      done; \
    done; \
    sed -i 's/#76CFA6/#070611/g' /app/manifest.json

# Injeta o CSS custom no index.html em build-time.
RUN sed -i 's#</head>#<link rel="stylesheet" href="/branding/custom.css?v=2"></head>#' /app/index.html \
 && grep -q '/branding/custom.css' /app/index.html

# Injeta as correcoes de runtime sobre o Element oficial (bundle minificado, nao da p/
# corrigir no fonte sem buildar tudo). Um arquivo so, uma tag so:
#   1. audio Opus/Ogg do FluffyChat (Ogg sem flag EOS + fallback WAV alimentado com
#      ArrayBuffer ja destacado por decodeAudioData);
#   2. target="_blank" nos links INTERNOS da tela de boas-vindas — o sanitizador
#      (Linkify.ts, transformTags.a) so o remove p/ permalinks Matrix ou URLs que casem
#      com ELEMENT_URL_PATTERN, que e montado de window.location em runtime (nao ha
#      config p/ isso); um href relativo como "#/login" ficava com _blank.
RUN sed -i 's#</head>#<script src="/branding/element-fixes.js?v=1"></script></head>#' /app/index.html \
 && grep -q '/branding/element-fixes.js' /app/index.html


# i18n pt-BR: as traducoes do Element vem do Localazy e ficam atras das releases, entao a
# UI mostra ingles (ex.: "Unreads"/"People"/"Rooms" nos filtros) ou ate a chave crua
# (release_announcement|room_list_section_title) quando o fallback nao resolve.
# 1) Aplica as traducoes de branding/i18n-ptbr-extra.json (256 chaves que faltavam);
# 2) Completa o resto com o en_EN (o que um fallback funcional faria) para nunca sobrar
#    chave crua. `jq -s '.[0] * .[1]'` = merge recursivo, o operando da DIREITA vence.
# Idempotente/auto-curavel: a traducao do upstream, quando vier, vence a do en_EN; e as
# nossas (extra) vencem as duas. Os i18n sao servidos sem `Cache-Control: immutable`
# (so etag/last-modified), entao sobrescrever no lugar e seguro.
RUN set -eu; \
    en="$(ls /app/i18n/en_EN.*.json | head -1)"; \
    ptbr="$(ls /app/i18n/pt_BR.*.json | head -1)"; \
    jq -s '.[0] * .[1] * .[2]' "$en" "$ptbr" /app/branding/i18n-ptbr-extra.json > "$ptbr.tmp" \
      && mv "$ptbr.tmp" "$ptbr"; \
    pt="$(ls /app/i18n/pt.*.json 2>/dev/null | head -1 || true)"; \
    if [ -n "$pt" ]; then jq -s '.[0] * .[1]' "$en" "$pt" > "$pt.tmp" && mv "$pt.tmp" "$pt"; fi; \
    jq -e '.room_list.filters.unread == "Não lidas"' "$ptbr" > /dev/null; \
    jq -e '.action.cancel == "Cancelar"' "$ptbr" > /dev/null; \
    rm -f /app/branding/i18n-ptbr-extra.json

# Templates (homeserver + marca via env) + entrypoint que os gera e sobe o nginx.
COPY config.json.template /app/config.json.template
COPY welcome.html.template /app/branding/welcome.html.template
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.title="Element (white-label)" \
      org.opencontainers.image.description="Element Web com branding white-label (paleta marcelomatos.dev); homeserver e marca via env" \
      org.opencontainers.image.source="https://github.com/marcelofmatos/element" \
      org.opencontainers.image.vendor="Marcelo Matos" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

# Sobe via entrypoint proprio (gera config + welcome + exec nginx). nginx escuta 8080.
ENTRYPOINT ["/docker-entrypoint.sh"]
