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
RUN sed -i 's#</head>#<link rel="stylesheet" href="/branding/custom.css?v=1"></head>#' /app/index.html \
 && grep -q '/branding/custom.css' /app/index.html

# Injeta o shim que conserta a reproducao de mensagens de voz Opus/Ogg (ex.: FluffyChat).
# O Element alimenta seu fallback WAV com um ArrayBuffer ja destacado por decodeAudioData(),
# entao o fallback nunca roda e o audio nao toca. O shim entrega uma copia ao decodificador
# nativo, preservando o buffer do chamador. Ver specs/spec-element-web-opus-fluffychat.md
RUN sed -i 's#</head>#<script src="/branding/opus-fix.js?v=1"></script></head>#' /app/index.html \
 && grep -q '/branding/opus-fix.js' /app/index.html

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
