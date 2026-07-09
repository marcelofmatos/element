/*
 * Correção: mensagens de voz Opus/Ogg (ex.: gravadas no FluffyChat) não tocam no
 * Element Web — o player fica vermelho com "Erro ao baixar o áudio".
 *
 * Causa raiz (ver specs/spec-element-web-opus-fluffychat.md):
 *   1. O decodificador nativo do navegador rejeita o Opus/Ogg do FluffyChat.
 *   2. O Element tem um fallback que reencoda para WAV via WASM (`decodeOgg`), mas o
 *      alimenta com o MESMO ArrayBuffer que acabou de passar por `decodeAudioData()`.
 *      Pela spec da Web Audio API, `decodeAudioData()` DESTACA (neutraliza) o buffer de
 *      entrada de forma sincrona — inclusive quando a decodificacao FALHA. O fallback
 *      entao recebe um buffer destacado, estoura "attempting to access detached
 *      ArrayBuffer" e nunca chega a rodar.
 *
 * Correcao aplicada aqui: envolvemos `decodeAudioData` para entregar ao decodificador
 * nativo uma COPIA do buffer. Assim o buffer do chamador jamais e destacado, o fallback
 * WASM do proprio Element roda e o audio toca.
 *
 * Patch de runtime (nao exige buildar o Element do fonte). E inofensivo se o upstream
 * corrigir: no pior caso faz uma copia a mais de um buffer pequeno (audios > 5 MB nem
 * passam por este caminho — vao pelo elemento <audio>).
 */
(function () {
    "use strict";

    var protos = [];
    if (typeof BaseAudioContext !== "undefined" && BaseAudioContext.prototype) {
        protos.push(BaseAudioContext.prototype);
    } else {
        if (typeof AudioContext !== "undefined") protos.push(AudioContext.prototype);
        if (typeof OfflineAudioContext !== "undefined") protos.push(OfflineAudioContext.prototype);
    }

    protos.forEach(function (proto) {
        var native = proto.decodeAudioData;
        if (typeof native !== "function" || native.__opusFixApplied) return;

        function decodeAudioData(audioData) {
            var args = Array.prototype.slice.call(arguments);
            // Um ArrayBuffer ja destacado tem byteLength 0 e slice() lancaria; nesse caso
            // deixamos o nativo reportar o erro normalmente.
            if (audioData instanceof ArrayBuffer && audioData.byteLength > 0) {
                try {
                    args[0] = audioData.slice(0);
                } catch (e) {
                    /* mantem o buffer original */
                }
            }
            return native.apply(this, args);
        }

        decodeAudioData.__opusFixApplied = true;
        proto.decodeAudioData = decodeAudioData;
    });
})();
