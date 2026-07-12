#!/bin/sh
# Gera o config.json e o welcome.html do Element a partir dos templates (homeserver e
# nome da marca via env) e sobe o nginx. Branding white-label (paleta marcelomatos.dev)
# é criado na imagem; so o homeserver e o nome da marca sao configuraveis em runtime.
set -e

: "${ELEMENT_BASE_URL:=https://matrix.example.com}"
: "${ELEMENT_SERVER_NAME:=example.com}"
: "${ELEMENT_BRAND:=Chat}"
# Frase de destaque da tela de boas-vindas. Aceita HTML simples (<strong>, <em>, <br>):
# o Element sanitiza o welcome_url ao renderizar, entao tags perigosas sao removidas.
# Vazia ("") esconde o paragrafo (ver .mx_WelcomePage_body p:empty no custom.css) — por isso
# usa '=' e nao ':=' (':=' trocaria a string vazia pelo default, impedindo esconder a frase).
: "${ELEMENT_TAGLINE=Converse em tempo real com sua equipe e seus clientes num chat <strong>seguro</strong> e <strong>criptografado</strong>, direto do navegador.}"
export ELEMENT_BASE_URL ELEMENT_SERVER_NAME ELEMENT_BRAND ELEMENT_TAGLINE

# Substitui APENAS estas vars (o tema usa '#', nao '$', entao e seguro).
# nginx root = /usr/share/nginx/html -> /app; o Element carrega /config.json daqui.
envsubst '${ELEMENT_BASE_URL} ${ELEMENT_SERVER_NAME} ${ELEMENT_BRAND}' \
  < /app/config.json.template \
  > /app/config.json

# Pagina de boas-vindas (embedded_pages.welcome_url) com o nome da marca e a frase.
envsubst '${ELEMENT_BRAND} ${ELEMENT_TAGLINE}' \
  < /app/branding/welcome.html.template \
  > /app/branding/welcome.html

echo "element: config.json + welcome.html gerados (base_url=${ELEMENT_BASE_URL}, server_name=${ELEMENT_SERVER_NAME}, brand=${ELEMENT_BRAND})"

exec nginx -g 'daemon off;'
