/*
 * Verificação do shim `branding/opus-fix.js` (spec-element-web-opus-fluffychat.md).
 *
 * Como rodar: abra o Element servido pela imagem, cole no console do navegador (DevTools)
 * e leia o PASS/FAIL. Também roda via Playwright com page.evaluate().
 *
 * Baseline (numa página SEM o shim) deve dar FAIL no teste 1 — é a reprodução do bug.
 */
(async () => {
    const results = [];
    const assert = (name, ok, detail) => results.push({ name, status: ok ? "PASS" : "FAIL", detail });

    const shimAtivo = !!BaseAudioContext.prototype.decodeAudioData.__opusFixApplied;
    assert("shim carregado", shimAtivo, `__opusFixApplied=${shimAtivo}`);

    const ctx = new OfflineAudioContext(1, 1024, 44100);

    // Teste 1 (o bug): decodeAudioData falha e NÃO pode destacar o buffer do chamador,
    // senão o fallback WAV do Element (decodeOgg -> new Uint8Array(buf)) nunca roda.
    const bad = new Uint8Array([0x4f, 0x67, 0x67, 0x53, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    const buf = bad.buffer;
    let rejeitou = false;
    try {
        await ctx.decodeAudioData(buf);
    } catch (e) {
        rejeitou = true;
    }
    assert("decodeAudioData rejeita áudio inválido", rejeitou, "erro propaga p/ o catch do Element");
    assert("buffer do chamador NÃO é destacado", buf.byteLength > 0, `byteLength=${buf.byteLength} (esperado > 0)`);

    let fallbackRoda = false;
    try {
        new Uint8Array(buf); // exatamente o que compat.ts:35 faz
        fallbackRoda = true;
    } catch (e) {
        fallbackRoda = false;
    }
    assert("fallback WASM consegue ler o buffer", fallbackRoda, "new Uint8Array(this.buf) não lança");

    // Teste 2 (regressão): áudio válido continua decodificando pelo caminho nativo.
    const rate = 8000,
        n = rate,
        ab = new ArrayBuffer(44 + n * 2),
        dv = new DataView(ab);
    const w = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
    w(0, "RIFF"); dv.setUint32(4, 36 + n * 2, true); w(8, "WAVEfmt ");
    dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true);
    dv.setUint32(24, rate, true); dv.setUint32(28, rate * 2, true); dv.setUint16(32, 2, true); dv.setUint16(34, 16, true);
    w(36, "data"); dv.setUint32(40, n * 2, true);
    for (let i = 0; i < n; i++) dv.setInt16(44 + i * 2, Math.sin(i / 10) * 3000, true);

    let decodedOk = false, dur = null;
    try {
        const decoded = await ctx.decodeAudioData(ab);
        dur = decoded.duration;
        decodedOk = Math.abs(dur - 1) < 0.01;
    } catch (e) { /* decodedOk = false */ }
    assert("WAV válido ainda decodifica (sem regressão)", decodedOk, `duration=${dur}`);

    // Teste 3: o WASM do fallback existe no servidor.
    let wasmOk = false;
    try {
        const r = await fetch("/decoderWorker.min.wasm", { method: "HEAD" });
        wasmOk = r.ok;
    } catch (e) { /* wasmOk = false */ }
    assert("decoderWorker.min.wasm servido", wasmOk, "sem ele o fallback não decodifica");

    console.table(results);
    const falhou = results.filter((r) => r.status === "FAIL");
    console.log(falhou.length ? `❌ ${falhou.length} FAIL` : `✅ ${results.length}/${results.length} PASS`);
    return results;
})();
