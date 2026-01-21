/**
 * MnemonicDemo - Interactive mnemonic checksum demonstration
 *
 * Shows how ASH generates human-readable checksums from pad bytes:
 * - 6 words from a 512-word wordlist (54 bits of entropy)
 * - Both parties can verbally verify the checksum matches
 */
import { useState, useEffect, useCallback } from 'react';

interface WasmModule {
  generate_mnemonic: (padBytes: Uint8Array) => string;
  generate_mnemonic_n: (padBytes: Uint8Array, wordCount: number) => string;
  bytes_to_hex: (bytes: Uint8Array) => string;
  default: () => Promise<void>;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).toUpperCase().padStart(2, '0')).join('');
}

function generateRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

export default function MnemonicDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [padBytes, setPadBytes] = useState<Uint8Array>(() => generateRandomBytes(32));
  const [mnemonic, setMnemonic] = useState<string[]>([]);
  const [wordCount, setWordCount] = useState(6);

  // Initialize WASM
  useEffect(() => {
    async function initWasm() {
      try {
        const importFn = new Function('url', 'return import(url)');
        const module = await importFn('/wasm/ash_wasm.js') as WasmModule;
        await module.default();
        setWasmModule(module);
        setWasmReady(true);
      } catch (e) {
        console.warn('WASM init failed:', e);
      }
    }
    initWasm();
  }, []);

  // Generate mnemonic when pad changes
  useEffect(() => {
    if (!wasmReady || !wasmModule) return;

    try {
      const words = wasmModule.generate_mnemonic_n(padBytes, wordCount);
      setMnemonic(words.split(' '));
    } catch (e) {
      console.error('Mnemonic error:', e);
    }
  }, [padBytes, wordCount, wasmModule, wasmReady]);

  const regeneratePad = useCallback(() => {
    setPadBytes(generateRandomBytes(32));
  }, []);

  // Calculate bit indices for visualization
  const getBitInfo = (wordIndex: number) => {
    // Each word uses 9 bits (512 words = 2^9)
    const startBit = wordIndex * 9;
    const startByte = Math.floor(startBit / 8);
    const endByte = Math.floor((startBit + 8) / 8);
    return { startBit, startByte, endByte };
  };

  return (
    <div className="bg-bg-card border border-border rounded-2xl overflow-hidden">
      <div className="px-4 py-3 border-b border-border bg-bg-elevated flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-success animate-pulse"></div>
          <h3 className="font-semibold text-white">Live Mnemonic Demo</h3>
        </div>
        <span className="text-xs text-text-muted px-2 py-1 bg-brand/20 text-brand-light rounded">
          {wasmReady ? 'Rust WASM' : 'Loading...'}
        </span>
      </div>

      <div className="p-5 space-y-6">
        {/* Pad Bytes Visualization */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium text-text-secondary">
              Pad bytes (first 32 of shared pad)
            </span>
            <button
              onClick={regeneratePad}
              className="text-xs text-brand hover:text-brand-light flex items-center gap-1"
            >
              <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              Regenerate
            </button>
          </div>

          <div className="bg-bg-elevated rounded-lg p-4">
            <div className="flex flex-wrap gap-1 font-mono text-xs">
              {Array.from(padBytes).map((byte, i) => {
                // Highlight bytes used for each word
                const isUsed = i < Math.ceil((wordCount * 9) / 8);
                return (
                  <span
                    key={i}
                    className={`px-1.5 py-1 rounded ${
                      isUsed
                        ? 'bg-brand/20 text-brand-light'
                        : 'bg-bg-card text-text-muted'
                    }`}
                    title={`Byte ${i}: 0x${byte.toString(16).padStart(2, '0')}`}
                  >
                    {byte.toString(16).toUpperCase().padStart(2, '0')}
                  </span>
                );
              })}
            </div>
            <p className="text-xs text-text-muted mt-2">
              First {Math.ceil((wordCount * 9) / 8)} bytes used for {wordCount} words
              ({wordCount * 9} bits / 8 = {Math.ceil((wordCount * 9) / 8)} bytes)
            </p>
          </div>
        </div>

        {/* Word Count Selector */}
        <div>
          <label className="block text-sm font-medium text-text-secondary mb-2">
            Word count (9 bits per word)
          </label>
          <div className="flex gap-2">
            {[4, 6, 8].map((count) => (
              <button
                key={count}
                onClick={() => setWordCount(count)}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                  wordCount === count
                    ? 'bg-brand text-white'
                    : 'bg-bg-elevated text-text-secondary hover:text-white'
                }`}
              >
                {count} words
                <span className="text-xs ml-1 opacity-70">({count * 9} bits)</span>
              </button>
            ))}
          </div>
        </div>

        {/* Generated Mnemonic */}
        {mnemonic.length > 0 && (
          <div className="bg-success/10 border border-success/30 rounded-xl p-5">
            <div className="flex items-center gap-2 mb-4">
              <svg className="w-5 h-5 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span className="text-sm font-medium text-success">Generated Mnemonic Checksum</span>
            </div>

            <div className="flex flex-wrap gap-3">
              {mnemonic.map((word, i) => {
                const bitInfo = getBitInfo(i);
                return (
                  <div key={i} className="flex flex-col items-center">
                    <span className="text-[10px] text-text-muted mb-1">
                      bits {bitInfo.startBit}-{bitInfo.startBit + 8}
                    </span>
                    <span className="px-4 py-2 bg-bg-elevated rounded-lg text-lg font-medium text-white">
                      {word}
                    </span>
                    <span className="text-[10px] text-text-muted mt-1">
                      word {i + 1}
                    </span>
                  </div>
                );
              })}
            </div>

            <p className="text-sm text-success mt-4">
              Both parties read these words aloud to verify pad integrity
            </p>
          </div>
        )}

        {/* Algorithm Explanation */}
        <div className="bg-bg-elevated rounded-lg p-4 space-y-3">
          <div className="text-sm font-medium text-white">How it works</div>
          <div className="space-y-2 text-xs text-text-secondary">
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-brand/20 rounded flex items-center justify-center text-brand text-[10px] font-bold">1</span>
              <span>Extract bits from pad bytes (big-endian bit stream)</span>
            </div>
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-brand/20 rounded flex items-center justify-center text-brand text-[10px] font-bold">2</span>
              <span>Group into 9-bit chunks (0-511 range)</span>
            </div>
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-brand/20 rounded flex items-center justify-center text-brand text-[10px] font-bold">3</span>
              <span>Look up each index in 512-word list</span>
            </div>
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-success/20 rounded flex items-center justify-center text-success text-[10px] font-bold">4</span>
              <span>Both parties get identical words (deterministic)</span>
            </div>
          </div>
        </div>

        {/* Properties Table */}
        <div className="bg-bg-elevated rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <tbody className="divide-y divide-border">
              <tr>
                <td className="px-4 py-2 text-text-muted">Wordlist size</td>
                <td className="px-4 py-2 text-text-secondary">512 words (custom, not BIP-39)</td>
              </tr>
              <tr>
                <td className="px-4 py-2 text-text-muted">Bits per word</td>
                <td className="px-4 py-2 text-text-secondary">9 bits (512 = 2^9)</td>
              </tr>
              <tr>
                <td className="px-4 py-2 text-text-muted">Default words</td>
                <td className="px-4 py-2 text-text-secondary">6 words = 54 bits</td>
              </tr>
              <tr>
                <td className="px-4 py-2 text-text-muted">Collision probability</td>
                <td className="px-4 py-2 text-text-secondary">~2^-54 (1 in 18 quadrillion)</td>
              </tr>
            </tbody>
          </table>
        </div>

        {/* Explanation */}
        <div className="text-xs text-text-muted border-t border-border pt-4">
          <p>
            <strong className="text-white">Why verbal verification?</strong> The mnemonic provides
            an out-of-band check that both devices have identical pads. Words are chosen for
            distinct pronunciation — no homophones, no easily confused words.
          </p>
        </div>
      </div>
    </div>
  );
}
