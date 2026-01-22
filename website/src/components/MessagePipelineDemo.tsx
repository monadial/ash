/**
 * MessagePipelineDemo - Complete message processing pipeline visualization
 *
 * Shows the full symmetric encryption/decryption pipeline using Rust FFI:
 *
 * SENDER:
 * 1. Padding - Traffic analysis protection
 * 2. OTP Encryption - XOR with pad bytes
 * 3. Wegman-Carter MAC - 256-bit authentication tag
 *
 * RECEIVER:
 * 1. Verify MAC - Reject if tampered
 * 2. OTP Decryption - XOR is symmetric
 * 3. Remove Padding - Extract original message
 */
import { useState, useEffect, useRef } from 'react';

interface WasmModule {
  pad_message: (message: Uint8Array) => Uint8Array;
  unpad_message: (padded: Uint8Array) => Uint8Array;
  otp_encrypt: (key: Uint8Array, plaintext: Uint8Array) => Uint8Array;
  otp_decrypt: (key: Uint8Array, ciphertext: Uint8Array) => Uint8Array;
  compute_auth_tag: (authKey: Uint8Array, header: Uint8Array, ciphertext: Uint8Array) => Uint8Array;
  verify_auth_tag: (authKey: Uint8Array, header: Uint8Array, ciphertext: Uint8Array, tag: Uint8Array) => boolean;
  default: () => Promise<void>;
}

const AUTH_KEY_SIZE = 64;
const FRAME_HEADER = new Uint8Array([0x01, 0x01, 0x00, 0x20]);

const EXAMPLE_MESSAGES = ['hi', 'Hello!', 'yes', 'Meet at 3pm', 'OK'];

function bytesToHex(bytes: Uint8Array, limit?: number): string {
  const arr = limit ? Array.from(bytes.slice(0, limit)) : Array.from(bytes);
  return arr.map(b => b.toString(16).toUpperCase().padStart(2, '0')).join(' ');
}

function generateRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

interface PipelineState {
  plaintext: string;
  plaintextBytes: Uint8Array;
  padded: Uint8Array;
  encKey: Uint8Array;
  ciphertext: Uint8Array;
  tamperedCiphertext: Uint8Array;
  tamperedByteIndex: number;
  authKey: Uint8Array;
  tag: Uint8Array;
  verified: boolean;
  tamperedVerified: boolean;
  decrypted: Uint8Array;
  unpadded: string;
}

export default function MessagePipelineDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [wasmError, setWasmError] = useState(false);
  const [messageIndex, setMessageIndex] = useState(0);
  const [pipeline, setPipeline] = useState<PipelineState | null>(null);
  const [activeStep, setActiveStep] = useState(0);
  const [showReceiver, setShowReceiver] = useState(false);
  const [simulateTamper, setSimulateTamper] = useState(false);
  const intervalRef = useRef<number | null>(null);

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
        setWasmError(true);
      }
    }
    initWasm();
  }, []);

  // Process message through pipeline
  useEffect(() => {
    if (!wasmReady || !wasmModule) return;

    const plaintext = EXAMPLE_MESSAGES[messageIndex];
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const plaintextBytes = encoder.encode(plaintext);

    try {
      // SENDER SIDE
      const padded = wasmModule.pad_message(plaintextBytes);
      const encKey = generateRandomBytes(padded.length);
      const ciphertext = wasmModule.otp_encrypt(encKey, padded);
      const authKey = generateRandomBytes(AUTH_KEY_SIZE);
      const tag = wasmModule.compute_auth_tag(authKey, FRAME_HEADER, ciphertext);

      // Create tampered ciphertext (flip one bit)
      const tamperedCiphertext = new Uint8Array(ciphertext);
      const tamperedByteIndex = Math.floor(ciphertext.length / 2);
      tamperedCiphertext[tamperedByteIndex] ^= 0x01; // Flip one bit

      // RECEIVER SIDE (using same keys - simulating shared pad)
      const verified = wasmModule.verify_auth_tag(authKey, FRAME_HEADER, ciphertext, tag);
      const tamperedVerified = wasmModule.verify_auth_tag(authKey, FRAME_HEADER, tamperedCiphertext, tag);
      const decrypted = wasmModule.otp_decrypt(encKey, ciphertext);
      const unpaddedBytes = wasmModule.unpad_message(decrypted);
      const unpadded = decoder.decode(unpaddedBytes);

      setPipeline({
        plaintext,
        plaintextBytes,
        padded,
        encKey,
        ciphertext,
        tamperedCiphertext,
        tamperedByteIndex,
        authKey,
        tag,
        verified,
        tamperedVerified,
        decrypted,
        unpadded,
      });
    } catch (e) {
      console.error('Pipeline error:', e);
    }
  }, [messageIndex, wasmModule, wasmReady]);

  // Auto-cycle through messages (pause when tampering)
  useEffect(() => {
    if (simulateTamper) {
      if (intervalRef.current) clearInterval(intervalRef.current);
      return;
    }
    intervalRef.current = window.setInterval(() => {
      setMessageIndex(i => (i + 1) % EXAMPLE_MESSAGES.length);
    }, 8000);
    return () => { if (intervalRef.current) clearInterval(intervalRef.current); };
  }, [simulateTamper]);

  // Animate through steps
  useEffect(() => {
    if (!pipeline) return;
    setActiveStep(0);
    setShowReceiver(false);
    const timers = [
      setTimeout(() => setActiveStep(1), 600),
      setTimeout(() => setActiveStep(2), 1200),
      setTimeout(() => setActiveStep(3), 1800),
      setTimeout(() => { setShowReceiver(true); setActiveStep(4); }, 2800),
      setTimeout(() => setActiveStep(5), 3400),
      setTimeout(() => setActiveStep(6), 4000),
      setTimeout(() => setActiveStep(7), 4600),
    ];
    return () => timers.forEach(clearTimeout);
  }, [pipeline]);

  // Show error state if WASM failed
  if (wasmError) {
    return (
      <div className="bg-bg-card border border-border rounded-2xl p-6">
        <div className="text-center text-text-muted">
          <p className="mb-2">Interactive demo requires WebAssembly support.</p>
          <p className="text-xs">See the static diagrams above for the pipeline flow.</p>
        </div>
      </div>
    );
  }

  if (!pipeline) {
    return (
      <div className="bg-bg-card border border-border rounded-2xl p-8 text-center">
        <div className="animate-pulse text-text-muted">Loading pipeline demo...</div>
      </div>
    );
  }

  return (
    <div className="bg-bg-card border border-border rounded-2xl overflow-hidden">
      <div className="px-4 py-3 border-b border-border bg-bg-elevated flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full ${simulateTamper ? 'bg-danger' : 'bg-success'} animate-pulse`}></div>
          <h3 className="font-semibold text-white">Live Message Pipeline</h3>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setSimulateTamper(!simulateTamper)}
            className={`text-xs px-3 py-1 rounded-full border transition-colors ${
              simulateTamper
                ? 'bg-danger/20 border-danger/50 text-danger'
                : 'bg-bg-card border-border text-text-muted hover:text-white hover:border-danger/50'
            }`}
          >
            {simulateTamper ? '⚠ Tampering Active' : 'Simulate Attack'}
          </button>
          <span className="text-xs px-2 py-1 bg-brand/20 text-brand-light rounded">Rust FFI</span>
        </div>
      </div>

      <div className="p-5">
        {/* Input */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <span className="text-sm text-text-muted">Message:</span>
            <code className="px-3 py-1.5 bg-brand/20 text-brand-light rounded-lg text-lg font-mono">"{pipeline.plaintext}"</code>
            <span className="text-xs text-text-muted">({pipeline.plaintextBytes.length}B)</span>
          </div>
          <div className="flex gap-1">
            {EXAMPLE_MESSAGES.map((_, i) => (
              <button key={i} onClick={() => setMessageIndex(i)}
                className={`w-2 h-2 rounded-full transition-colors ${i === messageIndex ? 'bg-brand' : 'bg-bg-elevated hover:bg-bg-hover'}`} />
            ))}
          </div>
        </div>

        {/* Two-column layout */}
        <div className="grid md:grid-cols-2 gap-6">
          {/* SENDER */}
          <div>
            <div className="flex items-center gap-2 mb-4">
              <div className="w-8 h-8 rounded-full bg-brand/20 flex items-center justify-center">
                <svg className="w-4 h-4 text-brand" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M7 11l5-5m0 0l5 5m-5-5v12" />
                </svg>
              </div>
              <div>
                <h4 className="font-semibold text-white">Sender</h4>
                <p className="text-text-muted text-xs">Pad → Encrypt → Authenticate</p>
              </div>
            </div>

            <div className="space-y-3">
              {/* Step 1: Padding */}
              <div className={`transition-all duration-300 ${activeStep >= 1 ? 'opacity-100' : 'opacity-30'}`}>
                <div className="flex items-center gap-2 mb-2">
                  <span className="w-5 h-5 bg-brand rounded text-white text-xs font-bold flex items-center justify-center">1</span>
                  <span className="text-sm font-medium text-white">Padding</span>
                  <span className="text-xs text-text-muted">→ {pipeline.padded.length}B</span>
                </div>
                <div className="ml-7 bg-bg-elevated rounded p-2">
                  <div className="flex flex-wrap gap-0.5 font-mono text-[9px]">
                    {Array.from(pipeline.padded).map((byte, i) => {
                      let c = 'bg-bg-card text-text-muted';
                      if (i === 0) c = 'bg-warning/20 text-warning';
                      else if (i < 3) c = 'bg-brand/20 text-brand-light';
                      else if (i < 3 + pipeline.plaintextBytes.length) c = 'bg-success/20 text-success';
                      return <span key={i} className={`px-1 py-0.5 rounded ${c}`}>{byte.toString(16).toUpperCase().padStart(2, '0')}</span>;
                    })}
                  </div>
                </div>
              </div>

              {/* Step 2: Encryption */}
              <div className={`transition-all duration-300 ${activeStep >= 2 ? 'opacity-100' : 'opacity-30'}`}>
                <div className="flex items-center gap-2 mb-2">
                  <span className="w-5 h-5 bg-brand rounded text-white text-xs font-bold flex items-center justify-center">2</span>
                  <span className="text-sm font-medium text-white">OTP Encrypt</span>
                </div>
                <div className="ml-7 bg-bg-elevated rounded p-2 text-[10px] font-mono space-y-1">
                  <div><span className="text-text-muted">padded:</span> <span className="text-text-secondary">{bytesToHex(pipeline.padded, 8)}...</span></div>
                  <div className="text-brand">⊕ XOR</div>
                  <div><span className="text-text-muted">key:</span> <span className="text-success">{bytesToHex(pipeline.encKey, 8)}...</span></div>
                  <div className="pt-1 border-t border-border"><span className="text-text-muted">cipher:</span> <span className="text-warning">{bytesToHex(pipeline.ciphertext, 8)}...</span></div>
                </div>
              </div>

              {/* Step 3: MAC */}
              <div className={`transition-all duration-300 ${activeStep >= 3 ? 'opacity-100' : 'opacity-30'}`}>
                <div className="flex items-center gap-2 mb-2">
                  <span className="w-5 h-5 bg-brand rounded text-white text-xs font-bold flex items-center justify-center">3</span>
                  <span className="text-sm font-medium text-white">Authenticate</span>
                </div>
                <div className="ml-7 bg-bg-elevated rounded p-2 text-[10px] font-mono">
                  <div className="flex flex-wrap gap-1 mb-2">
                    <span className="px-1.5 py-0.5 bg-purple-500/20 text-purple-300 rounded">r₁</span>
                    <span className="px-1.5 py-0.5 bg-purple-500/20 text-purple-300 rounded">r₂</span>
                    <span className="px-1.5 py-0.5 bg-teal-500/20 text-teal-300 rounded">s₁</span>
                    <span className="px-1.5 py-0.5 bg-teal-500/20 text-teal-300 rounded">s₂</span>
                    <span className="text-text-muted ml-1">64B auth key</span>
                  </div>
                  <div><span className="text-text-muted">tag:</span> <span className="text-success">{bytesToHex(pipeline.tag, 12)}...</span></div>
                </div>
              </div>

              {/* Wire format */}
              <div className={`transition-all duration-300 ${activeStep >= 3 ? 'opacity-100' : 'opacity-30'}`}>
                <div className="ml-7 bg-success/10 border border-success/30 rounded p-2">
                  <div className="flex items-center gap-2 text-xs">
                    <svg className="w-4 h-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                    <span className="text-success font-medium">Wire: {4 + pipeline.ciphertext.length + 32}B</span>
                  </div>
                  <div className="flex flex-wrap gap-1 mt-1 text-[9px] font-mono">
                    <span className="px-1.5 py-0.5 bg-bg-elevated rounded text-text-muted">[hdr 4B]</span>
                    <span className="px-1.5 py-0.5 bg-warning/20 text-warning rounded">[cipher {pipeline.ciphertext.length}B]</span>
                    <span className="px-1.5 py-0.5 bg-success/20 text-success rounded">[tag 32B]</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* RECEIVER */}
          <div className={`transition-all duration-500 ${showReceiver ? 'opacity-100' : 'opacity-30'}`}>
            <div className="flex items-center gap-2 mb-4">
              <div className="w-8 h-8 rounded-full bg-success/20 flex items-center justify-center">
                <svg className="w-4 h-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17 13l-5 5m0 0l-5-5m5 5V6" />
                </svg>
              </div>
              <div>
                <h4 className="font-semibold text-white">Receiver</h4>
                <p className="text-text-muted text-xs">Verify → Decrypt → Unpad</p>
              </div>
            </div>

            <div className="space-y-3">
              {/* Tampering indicator */}
              {simulateTamper && activeStep >= 4 && (
                <div className="bg-danger/10 border border-danger/30 rounded p-2 text-[10px]">
                  <div className="flex items-center gap-2 text-danger font-medium mb-1">
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                    </svg>
                    <span>Attacker modified byte {pipeline.tamperedByteIndex}</span>
                  </div>
                  <div className="font-mono">
                    <span className="text-text-muted">original:</span> <span className="text-text-secondary">{pipeline.ciphertext[pipeline.tamperedByteIndex].toString(16).toUpperCase().padStart(2, '0')}</span>
                    <span className="text-danger mx-1">→</span>
                    <span className="text-danger">{pipeline.tamperedCiphertext[pipeline.tamperedByteIndex].toString(16).toUpperCase().padStart(2, '0')}</span>
                  </div>
                </div>
              )}

              {/* Step 4: Verify */}
              <div className={`transition-all duration-300 ${activeStep >= 5 ? 'opacity-100' : 'opacity-30'}`}>
                <div className="flex items-center gap-2 mb-2">
                  <span className={`w-5 h-5 ${simulateTamper ? 'bg-danger' : 'bg-success'} rounded text-white text-xs font-bold flex items-center justify-center`}>1</span>
                  <span className="text-sm font-medium text-white">Verify MAC</span>
                </div>
                <div className="ml-7 bg-bg-elevated rounded p-2 text-[10px]">
                  {simulateTamper ? (
                    <>
                      <div className="font-mono mb-1">
                        <span className="text-text-muted">expected tag:</span> <span className="text-brand-light">{bytesToHex(pipeline.tag, 6)}...</span>
                      </div>
                      <div className="font-mono mb-2">
                        <span className="text-text-muted">computed tag:</span> <span className="text-danger">(different - data was modified)</span>
                      </div>
                      <div className="flex items-center gap-1 text-danger">
                        <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
                        <span className="font-medium">REJECTED - tampering detected!</span>
                      </div>
                    </>
                  ) : (
                    <>
                      <div className="font-mono mb-1">
                        <span className="text-text-muted">computed:</span> <span className="text-brand-light">{bytesToHex(pipeline.tag, 8)}...</span>
                      </div>
                      <div className="font-mono mb-2">
                        <span className="text-text-muted">received:</span> <span className="text-brand-light">{bytesToHex(pipeline.tag, 8)}...</span>
                      </div>
                      <div className="flex items-center gap-1 text-success">
                        <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
                        <span>Tags match - authentic</span>
                      </div>
                    </>
                  )}
                </div>
              </div>

              {/* Step 5: Decrypt - only if not tampered */}
              <div className={`transition-all duration-300 ${activeStep >= 6 ? 'opacity-100' : 'opacity-30'} ${simulateTamper ? 'opacity-20 pointer-events-none' : ''}`}>
                <div className="flex items-center gap-2 mb-2">
                  <span className="w-5 h-5 bg-success rounded text-white text-xs font-bold flex items-center justify-center">2</span>
                  <span className="text-sm font-medium text-white">OTP Decrypt</span>
                  {simulateTamper && <span className="text-xs text-danger">(skipped)</span>}
                </div>
                <div className="ml-7 bg-bg-elevated rounded p-2 text-[10px] font-mono space-y-1">
                  <div><span className="text-text-muted">cipher:</span> <span className="text-warning">{bytesToHex(pipeline.ciphertext, 8)}...</span></div>
                  <div className="text-brand">⊕ XOR (same key)</div>
                  <div><span className="text-text-muted">key:</span> <span className="text-success">{bytesToHex(pipeline.encKey, 8)}...</span></div>
                  <div className="pt-1 border-t border-border"><span className="text-text-muted">padded:</span> <span className="text-text-secondary">{bytesToHex(pipeline.decrypted, 8)}...</span></div>
                </div>
              </div>

              {/* Step 6: Unpad - only if not tampered */}
              <div className={`transition-all duration-300 ${activeStep >= 7 ? 'opacity-100' : 'opacity-30'} ${simulateTamper ? 'opacity-20 pointer-events-none' : ''}`}>
                <div className="flex items-center gap-2 mb-2">
                  <span className="w-5 h-5 bg-success rounded text-white text-xs font-bold flex items-center justify-center">3</span>
                  <span className="text-sm font-medium text-white">Remove Padding</span>
                  {simulateTamper && <span className="text-xs text-danger">(skipped)</span>}
                </div>
                <div className="ml-7 bg-bg-elevated rounded p-2 text-[10px]">
                  <div className="font-mono mb-2">
                    <span className="text-text-muted">length:</span> <span className="text-brand-light">{pipeline.plaintextBytes.length}</span>
                    <span className="text-text-muted ml-2">extract bytes 3-{3 + pipeline.plaintextBytes.length - 1}</span>
                  </div>
                </div>
              </div>

              {/* Final output */}
              <div className={`transition-all duration-300 ${activeStep >= 7 ? 'opacity-100' : 'opacity-30'}`}>
                {simulateTamper ? (
                  <div className="ml-7 bg-danger/10 border border-danger/30 rounded p-3">
                    <div className="flex items-center gap-2">
                      <svg className="w-5 h-5 text-danger" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                      </svg>
                      <span className="text-lg text-danger font-semibold">Message Rejected</span>
                    </div>
                    <p className="text-xs text-text-muted mt-1">
                      MAC verification failed. The message was modified in transit — attacker's tampering detected and blocked.
                    </p>
                  </div>
                ) : (
                  <div className="ml-7 bg-success/10 border border-success/30 rounded p-3">
                    <div className="flex items-center gap-2">
                      <svg className="w-5 h-5 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                      </svg>
                      <code className="text-lg text-success font-mono">"{pipeline.unpadded}"</code>
                    </div>
                    <p className="text-xs text-text-muted mt-1">Message delivered with cryptographic proof of authenticity</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-6 pt-4 border-t border-border flex flex-wrap justify-between gap-2 text-xs text-text-muted">
          <span><strong className="text-white">Pad consumed:</strong> {AUTH_KEY_SIZE + pipeline.padded.length}B per message</span>
          {simulateTamper ? (
            <span className="text-danger">Tampering simulation active — click button above to disable</span>
          ) : (
            <span>Auto-cycles every 8s • Click "Simulate Attack" to see rejection</span>
          )}
        </div>
      </div>
    </div>
  );
}
