/**
 * TokenDemo - Interactive token derivation demonstration
 *
 * Shows how ASH derives authorization tokens from pad bytes:
 * - Conversation ID (bytes 0-31)
 * - Auth Token (bytes 32-95)
 * - Burn Token (bytes 96-159)
 */
import { useState, useEffect, useCallback } from 'react';

interface WasmModule {
  derive_conversation_id: (padBytes: Uint8Array) => string;
  derive_auth_token: (padBytes: Uint8Array) => string;
  derive_burn_token: (padBytes: Uint8Array) => string;
  get_min_pad_size_for_tokens: () => number;
  default: () => Promise<void>;
}

function generateRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

interface TokenInfo {
  name: string;
  value: string;
  range: string;
  purpose: string;
  color: string;
}

export default function TokenDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [padBytes, setPadBytes] = useState<Uint8Array | null>(null);
  const [minPadSize, setMinPadSize] = useState(160);
  const [tokens, setTokens] = useState<TokenInfo[]>([]);
  const [highlightedRange, setHighlightedRange] = useState<[number, number] | null>(null);

  // Initialize WASM
  useEffect(() => {
    async function initWasm() {
      try {
        const importFn = new Function('url', 'return import(url)');
        const module = await importFn('/wasm/ash_wasm.js') as WasmModule;
        await module.default();
        setWasmModule(module);
        setWasmReady(true);
        const minSize = module.get_min_pad_size_for_tokens();
        setMinPadSize(minSize);
        setPadBytes(generateRandomBytes(minSize));
      } catch (e) {
        console.warn('WASM init failed:', e);
      }
    }
    initWasm();
  }, []);

  // Derive tokens when pad changes
  useEffect(() => {
    if (!wasmReady || !wasmModule || !padBytes) return;

    try {
      const convId = wasmModule.derive_conversation_id(padBytes);
      const authToken = wasmModule.derive_auth_token(padBytes);
      const burnToken = wasmModule.derive_burn_token(padBytes);

      setTokens([
        {
          name: 'Conversation ID',
          value: convId,
          range: '0-31',
          purpose: 'Identifies conversation on relay',
          color: 'brand',
        },
        {
          name: 'Auth Token',
          value: authToken,
          range: '32-95',
          purpose: 'Authenticates API requests',
          color: 'success',
        },
        {
          name: 'Burn Token',
          value: burnToken,
          range: '96-159',
          purpose: 'Required for burn operations',
          color: 'danger',
        },
      ]);
    } catch (e) {
      console.error('Token derivation error:', e);
    }
  }, [padBytes, wasmModule, wasmReady]);

  const regeneratePad = useCallback(() => {
    setPadBytes(generateRandomBytes(minPadSize));
  }, [minPadSize]);

  const getRangeForToken = (range: string): [number, number] => {
    const [start, end] = range.split('-').map(Number);
    return [start, end];
  };

  return (
    <div className="bg-bg-card border border-border rounded-2xl overflow-hidden">
      <div className="px-4 py-3 border-b border-border bg-bg-elevated flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-success animate-pulse"></div>
          <h3 className="font-semibold text-white">Live Token Derivation</h3>
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
              Pad bytes (first {minPadSize} bytes)
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

          {padBytes && (
            <div className="bg-bg-elevated rounded-lg p-4">
              <div className="flex flex-wrap gap-0.5 font-mono text-[9px]">
                {Array.from(padBytes).map((byte, i) => {
                  let colorClass = 'bg-bg-card text-text-muted';

                  if (highlightedRange) {
                    const [start, end] = highlightedRange;
                    if (i >= start && i <= end) {
                      if (start === 0) colorClass = 'bg-brand/30 text-brand-light';
                      else if (start === 32) colorClass = 'bg-success/30 text-success';
                      else if (start === 96) colorClass = 'bg-danger/30 text-danger';
                    }
                  } else {
                    if (i < 32) colorClass = 'bg-brand/20 text-brand-light';
                    else if (i < 96) colorClass = 'bg-success/20 text-success';
                    else colorClass = 'bg-danger/20 text-danger';
                  }

                  return (
                    <span
                      key={i}
                      className={`px-1 py-0.5 rounded ${colorClass} transition-colors`}
                      title={`Byte ${i}: 0x${byte.toString(16).padStart(2, '0')}`}
                    >
                      {byte.toString(16).toUpperCase().padStart(2, '0')}
                    </span>
                  );
                })}
              </div>

              {/* Range Legend */}
              <div className="flex flex-wrap gap-4 mt-3 pt-3 border-t border-border text-xs">
                <div className="flex items-center gap-1">
                  <span className="w-3 h-3 bg-brand/20 rounded"></span>
                  <span className="text-text-muted">0-31: Conv ID</span>
                </div>
                <div className="flex items-center gap-1">
                  <span className="w-3 h-3 bg-success/20 rounded"></span>
                  <span className="text-text-muted">32-95: Auth Token</span>
                </div>
                <div className="flex items-center gap-1">
                  <span className="w-3 h-3 bg-danger/20 rounded"></span>
                  <span className="text-text-muted">96-159: Burn Token</span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Derived Tokens */}
        <div className="space-y-4">
          <div className="text-sm font-medium text-white">Derived Tokens</div>

          {tokens.map((token) => {
            const range = getRangeForToken(token.range);
            const colorClasses = {
              brand: {
                bg: 'bg-brand/10 border-brand/30',
                badge: 'bg-brand/20 text-brand-light',
                text: 'text-brand-light',
              },
              success: {
                bg: 'bg-success/10 border-success/30',
                badge: 'bg-success/20 text-success',
                text: 'text-success',
              },
              danger: {
                bg: 'bg-danger/10 border-danger/30',
                badge: 'bg-danger/20 text-danger',
                text: 'text-danger',
              },
            }[token.color] || { bg: '', badge: '', text: '' };

            return (
              <div
                key={token.name}
                className={`border rounded-xl p-4 ${colorClasses.bg} transition-all cursor-pointer`}
                onMouseEnter={() => setHighlightedRange(range)}
                onMouseLeave={() => setHighlightedRange(null)}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-white">{token.name}</span>
                    <span className={`text-xs px-2 py-0.5 rounded ${colorClasses.badge}`}>
                      bytes {token.range}
                    </span>
                  </div>
                  <span className="text-xs text-text-muted">{token.purpose}</span>
                </div>
                <code className={`text-xs font-mono ${colorClasses.text} break-all block bg-bg-elevated/50 rounded p-2`}>
                  {token.value}
                </code>
                <p className="text-[10px] text-text-muted mt-2">
                  64 hex chars = 32 bytes = 256 bits
                </p>
              </div>
            );
          })}
        </div>

        {/* Derivation Process */}
        <div className="bg-bg-elevated rounded-lg p-4 space-y-3">
          <div className="text-sm font-medium text-white">Derivation Algorithm</div>
          <div className="space-y-2 text-xs text-text-secondary">
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-brand/20 rounded flex items-center justify-center text-brand text-[10px] font-bold">1</span>
              <span>Extract specific byte range from pad</span>
            </div>
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-brand/20 rounded flex items-center justify-center text-brand text-[10px] font-bold">2</span>
              <span>XOR-fold to 32-byte output</span>
            </div>
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-brand/20 rounded flex items-center justify-center text-brand text-[10px] font-bold">3</span>
              <span>Apply domain separation constant (different for each token type)</span>
            </div>
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-brand/20 rounded flex items-center justify-center text-brand text-[10px] font-bold">4</span>
              <span>Multiple mixing rounds for diffusion</span>
            </div>
            <div className="flex items-start gap-3">
              <span className="flex-shrink-0 w-5 h-5 bg-success/20 rounded flex items-center justify-center text-success text-[10px] font-bold">5</span>
              <span>Encode as 64-character lowercase hex</span>
            </div>
          </div>
        </div>

        {/* Security Properties */}
        <div className="bg-bg-elevated rounded-lg overflow-hidden">
          <div className="px-4 py-2 border-b border-border">
            <span className="text-sm font-medium text-white">Security Properties</span>
          </div>
          <div className="p-4 space-y-2 text-xs text-text-secondary">
            <p><strong className="text-white">Deterministic:</strong> Same pad → same tokens on both devices</p>
            <p><strong className="text-white">Unpredictable:</strong> Without pad, tokens cannot be computed or forged</p>
            <p><strong className="text-white">Separated:</strong> Different tokens for different operations (defense in depth)</p>
            <p><strong className="text-white">Backend-safe:</strong> Backend stores only hash(token), can verify but not forge</p>
          </div>
        </div>

        {/* Explanation */}
        <div className="text-xs text-text-muted border-t border-border pt-4">
          <p>
            <strong className="text-white">Why separate tokens?</strong> If an attacker compromises
            the auth token (e.g., via API logs), they still cannot burn the conversation without
            the burn token. Each token provides independent authorization for its operation.
          </p>
        </div>
      </div>
    </div>
  );
}
