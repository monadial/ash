/**
 * PolyHashDemo - Interactive Wegman-Carter MAC demonstration
 *
 * This component demonstrates the GF(2^128) polynomial hashing used in ASH:
 * - Shows auth key breakdown (r₁, r₂, s₁, s₂)
 * - Computes authentication tags using actual Rust WASM
 * - Demonstrates tag verification
 * - Shows how message changes affect the tag
 */
import { useState, useEffect, useCallback } from 'react';

const AUTH_KEY_SIZE = 64;
const TAG_SIZE = 32;
const BLOCK_SIZE = 16; // 128 bits = 16 bytes

interface WasmModule {
  compute_auth_tag: (authKey: Uint8Array, header: Uint8Array, ciphertext: Uint8Array) => Uint8Array;
  verify_auth_tag: (authKey: Uint8Array, header: Uint8Array, ciphertext: Uint8Array, tag: Uint8Array) => boolean;
  bytes_to_hex: (bytes: Uint8Array) => string;
  hex_to_bytes: (hex: string) => Uint8Array;
  otp_encrypt: (key: Uint8Array, plaintext: Uint8Array) => Uint8Array;
  pad_message: (message: Uint8Array) => Uint8Array;
  default: () => Promise<void>;
}

// Utility functions
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).toUpperCase().padStart(2, '0')).join('');
}

function generateRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

// Split auth key into components
function splitAuthKey(authKey: Uint8Array): { r1: Uint8Array; r2: Uint8Array; s1: Uint8Array; s2: Uint8Array } {
  return {
    r1: authKey.slice(0, 16),
    r2: authKey.slice(16, 32),
    s1: authKey.slice(32, 48),
    s2: authKey.slice(48, 64),
  };
}

// Split data into 128-bit blocks
function splitIntoBlocks(data: Uint8Array): Uint8Array[] {
  const blocks: Uint8Array[] = [];
  for (let i = 0; i < data.length; i += BLOCK_SIZE) {
    const block = new Uint8Array(BLOCK_SIZE);
    const remaining = Math.min(BLOCK_SIZE, data.length - i);
    block.set(data.slice(i, i + remaining));
    blocks.push(block);
  }
  return blocks;
}

export default function PolyHashDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [message, setMessage] = useState('Hello, ASH!');
  const [authKey, setAuthKey] = useState<Uint8Array>(() => generateRandomBytes(AUTH_KEY_SIZE));
  const [header] = useState<Uint8Array>(new Uint8Array([0x01, 0x01, 0x00, 0x20])); // version, type, length
  const [encKey, setEncKey] = useState<Uint8Array>(() => generateRandomBytes(32));
  const [computedTag, setComputedTag] = useState<Uint8Array | null>(null);
  const [ciphertext, setCiphertext] = useState<Uint8Array | null>(null);
  const [isVerified, setIsVerified] = useState<boolean | null>(null);
  const [tamperedByte, setTamperedByte] = useState<number | null>(null);

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

  // Compute tag when inputs change
  useEffect(() => {
    if (!wasmReady || !wasmModule) return;

    try {
      const encoder = new TextEncoder();
      const messageBytes = encoder.encode(message);
      const padded = wasmModule.pad_message(messageBytes);

      // Adjust encryption key size if needed
      let key = encKey;
      if (padded.length !== encKey.length) {
        key = generateRandomBytes(padded.length);
        setEncKey(key);
      }

      const encrypted = wasmModule.otp_encrypt(key, padded);
      setCiphertext(encrypted);

      const tag = wasmModule.compute_auth_tag(authKey, header, encrypted);
      setComputedTag(tag);
      setTamperedByte(null);
      setIsVerified(null);
    } catch (e) {
      console.error('Computation error:', e);
    }
  }, [message, authKey, encKey, header, wasmModule, wasmReady]);

  const regenerateAuthKey = useCallback(() => {
    setAuthKey(generateRandomBytes(AUTH_KEY_SIZE));
  }, []);

  const verifyTag = useCallback(() => {
    if (!wasmModule || !ciphertext || !computedTag) return;
    const valid = wasmModule.verify_auth_tag(authKey, header, ciphertext, computedTag);
    setIsVerified(valid);
    setTamperedByte(null);
  }, [wasmModule, authKey, header, ciphertext, computedTag]);

  const tamperAndVerify = useCallback(() => {
    if (!wasmModule || !ciphertext || !computedTag) return;

    // Tamper with a random byte in ciphertext
    const tamperedCiphertext = new Uint8Array(ciphertext);
    const byteIndex = Math.floor(Math.random() * tamperedCiphertext.length);
    tamperedCiphertext[byteIndex] ^= 0xFF; // Flip all bits
    setTamperedByte(byteIndex);

    // Try to verify with tampered data
    const valid = wasmModule.verify_auth_tag(authKey, header, tamperedCiphertext, computedTag);
    setIsVerified(valid);
  }, [wasmModule, authKey, header, ciphertext, computedTag]);

  const keyParts = splitAuthKey(authKey);
  const blocks = ciphertext ? splitIntoBlocks(ciphertext) : [];

  return (
    <div className="bg-bg-card border border-border rounded-2xl overflow-hidden">
      <div className="px-4 py-3 border-b border-border bg-bg-elevated flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-success animate-pulse"></div>
          <h3 className="font-semibold text-white">Live Polynomial Hash Demo</h3>
        </div>
        <span className="text-xs text-text-muted px-2 py-1 bg-brand/20 text-brand-light rounded">
          {wasmReady ? 'Rust WASM' : 'Loading...'}
        </span>
      </div>

      <div className="p-5 space-y-6">
        {/* Input Section */}
        <div>
          <label className="block text-sm font-medium text-text-secondary mb-2">
            Message to authenticate
          </label>
          <input
            type="text"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Enter a message..."
            className="w-full bg-bg-elevated border border-border rounded-lg px-4 py-2.5 text-white font-mono text-sm focus:outline-none focus:border-brand"
          />
        </div>

        {/* Auth Key Breakdown */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium text-text-secondary">Authentication Key (64 bytes)</span>
            <button
              onClick={regenerateAuthKey}
              className="text-xs text-brand hover:text-brand-light flex items-center gap-1"
            >
              <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              Regenerate
            </button>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="bg-bg-elevated rounded-lg p-3">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-0.5 bg-brand/20 text-brand-light rounded text-xs font-medium">r₁</span>
                <span className="text-xs text-text-muted">Random point 1 (16B)</span>
              </div>
              <code className="text-[10px] text-text-secondary font-mono break-all">{bytesToHex(keyParts.r1)}</code>
            </div>
            <div className="bg-bg-elevated rounded-lg p-3">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-0.5 bg-brand/20 text-brand-light rounded text-xs font-medium">r₂</span>
                <span className="text-xs text-text-muted">Random point 2 (16B)</span>
              </div>
              <code className="text-[10px] text-text-secondary font-mono break-all">{bytesToHex(keyParts.r2)}</code>
            </div>
            <div className="bg-bg-elevated rounded-lg p-3">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-0.5 bg-success/20 text-success rounded text-xs font-medium">s₁</span>
                <span className="text-xs text-text-muted">OTP mask 1 (16B)</span>
              </div>
              <code className="text-[10px] text-text-secondary font-mono break-all">{bytesToHex(keyParts.s1)}</code>
            </div>
            <div className="bg-bg-elevated rounded-lg p-3">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-0.5 bg-success/20 text-success rounded text-xs font-medium">s₂</span>
                <span className="text-xs text-text-muted">OTP mask 2 (16B)</span>
              </div>
              <code className="text-[10px] text-text-secondary font-mono break-all">{bytesToHex(keyParts.s2)}</code>
            </div>
          </div>
        </div>

        {/* Ciphertext Blocks */}
        {ciphertext && (
          <div>
            <span className="text-sm font-medium text-text-secondary mb-3 block">
              Ciphertext Blocks ({blocks.length} × 128-bit)
            </span>
            <div className="flex flex-wrap gap-2">
              {blocks.map((block, i) => (
                <div key={i} className="bg-bg-elevated rounded px-3 py-2">
                  <div className="text-[10px] text-text-muted mb-1">Block {i + 1}</div>
                  <code className="text-[9px] text-warning font-mono">{bytesToHex(block).substring(0, 16)}...</code>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Polynomial Visualization */}
        <div className="bg-bg-elevated rounded-lg p-4">
          <div className="text-sm font-medium text-white mb-3">Polynomial Evaluation</div>
          <div className="space-y-2 text-xs">
            <div className="flex items-center gap-2">
              <span className="text-text-muted w-20">Polynomial:</span>
              <code className="text-brand-light">
                P(x) = {blocks.map((_, i) => `b${i + 1}·x${blocks.length - i > 1 ? `^${blocks.length - i}` : ''}`).join(' + ')}
              </code>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-text-muted w-20">Tag₁:</span>
              <code className="text-text-secondary">P(r₁) ⊕ s₁ = <span className="text-success">{computedTag ? bytesToHex(computedTag.slice(0, 16)) : '...'}</span></code>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-text-muted w-20">Tag₂:</span>
              <code className="text-text-secondary">P(r₂) ⊕ s₂ = <span className="text-success">{computedTag ? bytesToHex(computedTag.slice(16, 32)) : '...'}</span></code>
            </div>
          </div>
        </div>

        {/* Computed Tag */}
        {computedTag && (
          <div className="bg-success/10 border border-success/30 rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <svg className="w-4 h-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
              <span className="text-sm font-medium text-success">256-bit Authentication Tag</span>
            </div>
            <code className="text-xs text-white font-mono break-all block bg-bg-elevated rounded p-2">
              {bytesToHex(computedTag)}
            </code>
          </div>
        )}

        {/* Verification Section */}
        <div>
          <div className="text-sm font-medium text-text-secondary mb-3">Tag Verification</div>
          <div className="flex gap-3">
            <button
              onClick={verifyTag}
              disabled={!computedTag}
              className="px-4 py-2 bg-success/20 text-success text-sm font-medium rounded-lg hover:bg-success/30 transition-colors disabled:opacity-50"
            >
              Verify Tag
            </button>
            <button
              onClick={tamperAndVerify}
              disabled={!computedTag}
              className="px-4 py-2 bg-danger/20 text-danger text-sm font-medium rounded-lg hover:bg-danger/30 transition-colors disabled:opacity-50"
            >
              Tamper & Verify
            </button>
          </div>

          {isVerified !== null && (
            <div className={`mt-3 p-3 rounded-lg ${isVerified ? 'bg-success/10 border border-success/30' : 'bg-danger/10 border border-danger/30'}`}>
              <div className="flex items-center gap-2">
                {isVerified ? (
                  <>
                    <svg className="w-5 h-5 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                    <span className="text-success font-medium">Tag verified successfully!</span>
                  </>
                ) : (
                  <>
                    <svg className="w-5 h-5 text-danger" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                    <span className="text-danger font-medium">
                      Tag verification failed!
                      {tamperedByte !== null && <span className="text-text-muted font-normal"> (byte {tamperedByte} was tampered)</span>}
                    </span>
                  </>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Explanation */}
        <div className="text-xs text-text-muted border-t border-border pt-4">
          <p className="mb-2">
            <strong className="text-white">How it works:</strong> The message is padded and encrypted,
            then split into 128-bit blocks. Each block becomes a coefficient in a polynomial.
            The polynomial is evaluated at secret points r₁ and r₂ in GF(2^128), then XOR'd with
            one-time masks s₁ and s₂ to produce the final 256-bit tag.
          </p>
          <p>
            <strong className="text-white">Why it's secure:</strong> Without knowing r, an attacker
            cannot forge a valid tag for a different message. The probability of guessing is ~2^-128.
          </p>
        </div>
      </div>
    </div>
  );
}
