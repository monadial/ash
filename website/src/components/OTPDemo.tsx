/**
 * OTPDemo - Interactive One-Time Pad encryption demonstration
 *
 * This component demonstrates the XOR operation at the heart of OTP:
 * - Shows how plaintext XOR key = ciphertext
 * - Shows how ciphertext XOR key = plaintext
 * - Uses actual Rust WASM for encryption/decryption
 */
import { useState, useEffect, useCallback } from 'react';

interface WasmModule {
  otp_encrypt: (key: Uint8Array, plaintext: Uint8Array) => Uint8Array;
  otp_decrypt: (key: Uint8Array, ciphertext: Uint8Array) => Uint8Array;
  bytes_to_hex: (bytes: Uint8Array) => string;
  default: () => Promise<void>;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).toUpperCase().padStart(2, '0')).join(' ');
}

function generateRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

export default function OTPDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [message, setMessage] = useState('HELLO');
  const [key, setKey] = useState<Uint8Array | null>(null);
  const [ciphertext, setCiphertext] = useState<Uint8Array | null>(null);
  const [decrypted, setDecrypted] = useState<string | null>(null);

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

  // Generate key when message changes
  useEffect(() => {
    const encoder = new TextEncoder();
    const messageBytes = encoder.encode(message);
    setKey(generateRandomBytes(messageBytes.length));
  }, [message]);

  // Encrypt when message or key changes
  useEffect(() => {
    if (!wasmReady || !wasmModule || !key || message.length === 0) {
      setCiphertext(null);
      setDecrypted(null);
      return;
    }

    try {
      const encoder = new TextEncoder();
      const decoder = new TextDecoder();
      const messageBytes = encoder.encode(message);

      // Ensure key matches message length
      const currentKey = key.length === messageBytes.length ? key : generateRandomBytes(messageBytes.length);
      if (currentKey !== key) {
        setKey(currentKey);
        return;
      }

      const encrypted = wasmModule.otp_encrypt(currentKey, messageBytes);
      setCiphertext(encrypted);

      const decryptedBytes = wasmModule.otp_decrypt(currentKey, encrypted);
      setDecrypted(decoder.decode(decryptedBytes));
    } catch (e) {
      console.error('Encryption error:', e);
    }
  }, [message, key, wasmModule, wasmReady]);

  const regenerateKey = useCallback(() => {
    const encoder = new TextEncoder();
    const messageBytes = encoder.encode(message);
    setKey(generateRandomBytes(messageBytes.length));
  }, [message]);

  const encoder = new TextEncoder();
  const messageBytes = encoder.encode(message);

  return (
    <div className="bg-bg-card border border-border rounded-2xl overflow-hidden">
      <div className="px-4 py-3 border-b border-border bg-bg-elevated flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-success animate-pulse"></div>
          <h3 className="font-semibold text-white">Live OTP Encryption</h3>
        </div>
        <span className="text-xs text-text-muted px-2 py-1 bg-brand/20 text-brand-light rounded">
          {wasmReady ? 'Rust WASM' : 'Loading...'}
        </span>
      </div>

      <div className="p-5 space-y-6">
        {/* Message Input */}
        <div>
          <label className="block text-sm font-medium text-text-secondary mb-2">
            Plaintext message
          </label>
          <input
            type="text"
            value={message}
            onChange={(e) => setMessage(e.target.value.toUpperCase())}
            placeholder="Enter message..."
            maxLength={16}
            className="w-full bg-bg-elevated border border-border rounded-lg px-4 py-2.5 text-white font-mono text-lg tracking-widest focus:outline-none focus:border-brand uppercase"
          />
          <p className="text-xs text-text-muted mt-1">Max 16 characters</p>
        </div>

        {/* XOR Visualization */}
        {key && ciphertext && (
          <div className="bg-bg-elevated rounded-xl p-5 space-y-4">
            {/* Plaintext Row */}
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <span className="text-xs text-text-muted w-20">Plaintext:</span>
                <span className="text-sm text-brand-light font-mono">"{message}"</span>
              </div>
              <div className="flex flex-wrap gap-2 font-mono text-xs">
                {Array.from(messageBytes).map((byte, i) => (
                  <div key={i} className="flex flex-col items-center">
                    <span className="text-text-muted text-[10px] mb-1">{String.fromCharCode(byte)}</span>
                    <span className="px-2 py-1.5 bg-brand/20 text-brand-light rounded">
                      {byte.toString(16).toUpperCase().padStart(2, '0')}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            {/* XOR Symbol */}
            <div className="flex items-center gap-3">
              <span className="text-2xl text-brand font-bold">⊕</span>
              <span className="text-xs text-text-muted">XOR (bit-by-bit exclusive or)</span>
            </div>

            {/* Key Row */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="text-xs text-text-muted w-20">Key:</span>
                  <span className="text-xs text-success">(random bytes)</span>
                </div>
                <button
                  onClick={regenerateKey}
                  className="text-xs text-brand hover:text-brand-light flex items-center gap-1"
                >
                  <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                  New Key
                </button>
              </div>
              <div className="flex flex-wrap gap-2 font-mono text-xs">
                {Array.from(key).map((byte, i) => (
                  <div key={i} className="flex flex-col items-center">
                    <span className="text-text-muted text-[10px] mb-1">?</span>
                    <span className="px-2 py-1.5 bg-success/20 text-success rounded">
                      {byte.toString(16).toUpperCase().padStart(2, '0')}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            {/* Equals */}
            <div className="flex items-center">
              <span className="text-2xl text-text-muted">=</span>
            </div>

            {/* Ciphertext Row */}
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <span className="text-xs text-text-muted w-20">Ciphertext:</span>
                <span className="text-xs text-warning">(transmitted over network)</span>
              </div>
              <div className="flex flex-wrap gap-2 font-mono text-xs">
                {Array.from(ciphertext).map((byte, i) => (
                  <div key={i} className="flex flex-col items-center">
                    <span className="text-text-muted text-[10px] mb-1">?</span>
                    <span className="px-2 py-1.5 bg-warning/20 text-warning rounded">
                      {byte.toString(16).toUpperCase().padStart(2, '0')}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            {/* Bit-level Example */}
            <div className="mt-6 pt-4 border-t border-border">
              <div className="text-xs text-text-muted mb-3">Bit-level view (first byte):</div>
              <div className="space-y-2 font-mono text-xs">
                <div className="flex items-center gap-3">
                  <span className="text-text-muted w-20">Plaintext:</span>
                  <span className="text-brand-light tracking-wider">
                    {messageBytes[0]?.toString(2).padStart(8, '0')}
                  </span>
                  <span className="text-text-muted">({messageBytes[0]?.toString(16).toUpperCase().padStart(2, '0')} = '{String.fromCharCode(messageBytes[0])}')</span>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-text-muted w-20">Key:</span>
                  <span className="text-success tracking-wider">
                    {key[0]?.toString(2).padStart(8, '0')}
                  </span>
                  <span className="text-text-muted">({key[0]?.toString(16).toUpperCase().padStart(2, '0')})</span>
                </div>
                <div className="flex items-center gap-3 pt-1 border-t border-border/50">
                  <span className="text-text-muted w-20">Ciphertext:</span>
                  <span className="text-warning tracking-wider">
                    {ciphertext[0]?.toString(2).padStart(8, '0')}
                  </span>
                  <span className="text-text-muted">({ciphertext[0]?.toString(16).toUpperCase().padStart(2, '0')})</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Decryption Result */}
        {decrypted && (
          <div className="bg-success/10 border border-success/30 rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <svg className="w-4 h-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
              <span className="text-sm font-medium text-success">Decryption (ciphertext ⊕ key):</span>
            </div>
            <code className="text-lg text-white font-mono tracking-widest">{decrypted}</code>
          </div>
        )}

        {/* Explanation */}
        <div className="text-xs text-text-muted border-t border-border pt-4 space-y-2">
          <p>
            <strong className="text-white">XOR properties:</strong> The same operation encrypts and decrypts.
            If A ⊕ B = C, then C ⊕ B = A.
          </p>
          <p>
            <strong className="text-white">Perfect secrecy:</strong> Without the key, every possible
            plaintext is equally likely. "HELLO" could decrypt to any 5-letter message.
          </p>
        </div>
      </div>
    </div>
  );
}
