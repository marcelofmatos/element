#!/bin/sh
# Gera o config.json e o welcome.html do Element a partir dos templates (homeserver e
# nome da marca via env) e sobe o nginx. Branding white-label (paleta marcelomatos.dev)
# é criado na imagem; so o homeserver e o nome da marca sao configuraveis em runtime.
set -e

: "${ELEMENT_BASE_URL:=https://matrix.example.com}"
: "${ELEMENT_SERVER_NAME:=example.com}"
: "${ELEMENT_BRAND:=Chat}"
export ELEMENT_BASE_URL ELEMENT_SERVER_NAME ELEMENT_BRAND

# Substitui APENAS estas vars (o tema usa '#', nao '$', entao e seguro).
# nginx root = /usr/share/nginx/html -> /app; o Element carrega /config.json daqui.
envsubst '${ELEMENT_BASE_URL} ${ELEMENT_SERVER_NAME} ${ELEMENT_BRAND}' \
  < /app/config.json.template \
  > /app/config.json

# Pagina de boas-vindas (embedded_pages.welcome_url) com o nome da marca.
envsubst '${ELEMENT_BRAND}' \
  < /app/branding/welcome.html.template \
  > /app/branding/welcome.html

echo "element: config.json + welcome.html gerados (base_url=${ELEMENT_BASE_URL}, server_name=${ELEMENT_SERVER_NAME}, brand=${ELEMENT_BRAND})"

exec nginx -g 'daemon off;'
