/*
 * Correção: mensagens de voz Opus/Ogg (ex.: gravadas no FluffyChat) não tocam no
 * Element Web — o player fica vermelho ou nunca fica pronto.
 *
 * CAUSA RAIZ (medida, não suposta):
 *   O FluffyChat grava um Ogg cuja ULTIMA PAGINA nao tem a flag EOS (end-of-stream).
 *   O Opus em si esta intacto. Consequencias:
 *     - Firefox: `decodeAudioData` REJEITA o arquivo (EncodingError).
 *     - Chrome : `decodeAudioData` tolera e decodifica.
 *     - O fallback do Element (`decodeOgg`, WASM do opus-recorder) REJEITA nos dois
 *       navegadores: o worker nao emite nada. E como o `decodeOgg` do Element nao tem
 *       caminho de `reject` ("no reject because the workers don't seem to have a fail
 *       path", diz o proprio comentario dele), o `await` fica pendurado para sempre:
 *       `prepare()` nunca termina, o player nunca fica pronto e NENHUM erro e logado.
 *   Ligar o bit EOS na ultima pagina (e recalcular o CRC dela) faz o arquivo decodificar
 *   nos dois navegadores E no worker do Element.
 *
 * ALEM DISSO: `decodeAudioData` DESTACA (neutraliza) o ArrayBuffer de entrada de forma
 *   sincrona, inclusive quando a decodificacao falha (spec da Web Audio API). O Element
 *   alimentava o fallback com esse mesmo buffer ja destacado, e `new Uint8Array(buf)`
 *   lancava "attempting to access detached ArrayBuffer" — o fallback nunca rodava.
 *
 * O QUE ESTE SHIM FAZ (envolvendo `BaseAudioContext.prototype.decodeAudioData`):
 *   1. Entrega ao decodificador nativo uma COPIA do buffer → o buffer do chamador nunca
 *      e destacado.
 *   2. Se o nativo falhar e os bytes forem um Ogg sem EOS, repara (liga EOS + CRC) e
 *      tenta decodificar de novo. Dando certo, o Element nem chega no `decodeOgg` que trava.
 *   3. Se nao der para reparar, propaga o erro original (comportamento inalterado).
 *
 * Patch de runtime — nao exige buildar o Element do fonte. Inofensivo se o upstream
 * corrigir. Ver specs/spec-element-web-opus-fluffychat.md
 */
(function () {
    "use strict";

    var OGG_MAGIC = 0x4f676753; // "OggS"

    // CRC-32 do Ogg: polinomio 0x04c11db7, init 0, sem reflexao, sem xor final.
    var crcTable = null;
    function buildCrcTable() {
        var table = new Uint32Array(256);
        for (var i = 0; i < 256; i++) {
            var r = i << 24;
            for (var j = 0; j < 8; j++) {
                r = r & 0x80000000 ? ((r << 1) ^ 0x04c11db7) >>> 0 : (r << 1) >>> 0;
            }
            table[i] = r >>> 0;
        }
        return table;
    }
    function crc32Ogg(bytes) {
        if (!crcTable) crcTable = buildCrcTable();
        var crc = 0;
        for (var i = 0; i < bytes.length; i++) {
            crc = ((crc << 8) ^ crcTable[((crc >>> 24) ^ bytes[i]) & 0xff]) >>> 0;
        }
        return crc >>> 0;
    }

    /**
     * Se `buffer` for um Ogg cuja ultima pagina nao tem EOS, devolve uma COPIA reparada
     * (EOS ligado + CRC recalculado). Caso contrario devolve null.
     */
    function repairOggMissingEos(buffer) {
        var u8 = new Uint8Array(buffer);
        if (u8.length < 27) return null;
        var dv = new DataView(buffer);
        if (dv.getUint32(0, false) !== OGG_MAGIC) return null;

        var off = 0;
        var lastOff = -1;
        var lastLen = 0;
        while (off + 27 <= u8.length) {
            if (dv.getUint32(off, false) !== OGG_MAGIC) break;
            var nseg = u8[off + 26];
            if (off + 27 + nseg > u8.length) break;
            var body = 0;
            for (var s = 0; s < nseg; s++) body += u8[off + 27 + s];
            var pageLen = 27 + nseg + body;
            if (off + pageLen > u8.length) break;
            lastOff = off;
            lastLen = pageLen;
            off += pageLen;
        }
        if (lastOff < 0) return null;
        if (u8[lastOff + 5] & 0x04) return null; // ja tem EOS: nao e este o problema

        var out = buffer.slice(0);
        var o8 = new Uint8Array(out);
        o8[lastOff + 5] |= 0x04; // liga EOS
        o8[lastOff + 22] = 0;    // zera o campo de CRC antes de calcular
        o8[lastOff + 23] = 0;
        o8[lastOff + 24] = 0;
        o8[lastOff + 25] = 0;
        var crc = crc32Ogg(o8.subarray(lastOff, lastOff + lastLen));
        o8[lastOff + 22] = crc & 0xff;
        o8[lastOff + 23] = (crc >>> 8) & 0xff;
        o8[lastOff + 24] = (crc >>> 16) & 0xff;
        o8[lastOff + 25] = (crc >>> 24) & 0xff;
        return out;
    }

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

        function decodeAudioData(audioData, successCallback, errorCallback) {
            var ctx = this;

            var promise = (function () {
                // Buffer destacado (byteLength 0) ou tipo inesperado: deixa o nativo decidir.
                if (!(audioData instanceof ArrayBuffer) || audioData.byteLength === 0) {
                    return native.call(ctx, audioData);
                }
                // Copia: o nativo destaca a entrada mesmo quando falha.
                return native.call(ctx, audioData.slice(0)).catch(function (err) {
                    var repaired = null;
                    try {
                        repaired = repairOggMissingEos(audioData);
                    } catch (e) {
                        repaired = null;
                    }
                    if (!repaired) throw err;
                    return native.call(ctx, repaired);
                });
            })();

            if (typeof successCallback === "function" || typeof errorCallback === "function") {
                promise.then(
                    function (buf) { if (successCallback) successCallback(buf); },
                    function (err) { if (errorCallback) errorCallback(err); },
                );
            }
            return promise;
        }

        decodeAudioData.__opusFixApplied = true;
        proto.decodeAudioData = decodeAudioData;
    });
})();
