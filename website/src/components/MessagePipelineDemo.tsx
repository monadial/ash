/**
 * MessagePipelineDemo - Automatic message processing pipeline visualization
 *
 * Shows the complete encryption pipeline using actual Rust FFI:
 * 1. Padding - Traffic analysis protection
 * 2. OTP Encryption - XOR with pad bytes
 * 3. Wegman-Carter MAC - 256-bit authentication tag
 *
 * Auto-cycles through example messages to demonstrate the pipeline.
 */
import { useState, useEffect, useRef } from 'react';

interface WasmModule {
  pad_message: (message: Uint8Array) => Uint8Array;
  otp_encrypt: (key: Uint8Array, plaintext: Uint8Array) => Uint8Array;
  compute_auth_tag: (authKey: Uint8Array, header: Uint8Array, ciphertext: Uint8Array) => Uint8Array;
  bytes_to_hex: (bytes: Uint8Array) => string;
  default: () => Promise<void>;
}

const AUTH_KEY_SIZE = 64;
const FRAME_HEADER = new Uint8Array([0x01, 0x01, 0x00, 0x20]);

// Example messages to cycle through
const EXAMPLE_MESSAGES = [
  'hi',
  'Hello!',
  'yes',
  'Meet at 3pm',
  'OK',
];

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
  authKey: Uint8Array;
  tag: Uint8Array;
}

export default function MessagePipelineDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [messageIndex, setMessageIndex] = useState(0);
  const [pipeline, setPipeline] = useState<PipelineState | null>(null);
  const [activeStep, setActiveStep] = useState(0);
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
      }
    }
    initWasm();
  }, []);

  // Process message through pipeline
  useEffect(() => {
    if (!wasmReady || !wasmModule) return;

    const plaintext = EXAMPLE_MESSAGES[messageIndex];
    const encoder = new TextEncoder();
    const plaintextBytes = encoder.encode(plaintext);

    try {
      // Step 1: Padding
      const padded = wasmModule.pad_message(plaintextBytes);

      // Step 2: OTP Encryption
      const encKey = generateRandomBytes(padded.length);
      const ciphertext = wasmModule.otp_encrypt(encKey, padded);

      // Step 3: Authentication
      const authKey = generateRandomBytes(AUTH_KEY_SIZE);
      const tag = wasmModule.compute_auth_tag(authKey, FRAME_HEADER, ciphertext);

      setPipeline({
        plaintext,
        plaintextBytes,
        padded,
        encKey,
        ciphertext,
        authKey,
        tag,
      });
    } catch (e) {
      console.error('Pipeline error:', e);
    }
  }, [messageIndex, wasmModule, wasmReady]);

  // Auto-cycle through messages
  useEffect(() => {
    intervalRef.current = window.setInterval(() => {
      setMessageIndex(i => (i + 1) % EXAMPLE_MESSAGES.length);
    }, 5000);

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, []);

  // Animate through steps
  useEffect(() => {
    if (!pipeline) return;
    setActiveStep(0);
    const timer1 = setTimeout(() => setActiveStep(1), 800);
    const timer2 = setTimeout(() => setActiveStep(2), 1600);
    const timer3 = setTimeout(() => setActiveStep(3), 2400);
    return () => {
      clearTimeout(timer1);
      clearTimeout(timer2);
      clearTimeout(timer3);
    };
  }, [pipeline]);

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
          <div className="w-2 h-2 rounded-full bg-success animate-pulse"></div>
          <h3 className="font-semibold text-white">Live Message Pipeline</h3>
        </div>
        <span className="text-xs text-text-muted px-2 py-1 bg-brand/20 text-brand-light rounded">
          {wasmReady ? 'Rust FFI' : 'Loading...'}
        </span>
      </div>

      <div className="p-5 space-y-4">
        {/* Input Message */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="text-sm text-text-muted">Input:</span>
            <code className="px-3 py-1.5 bg-brand/20 text-brand-light rounded-lg text-lg font-mono">
              "{pipeline.plaintext}"
            </code>
            <span className="text-xs text-text-muted">({pipeline.plaintextBytes.length} bytes)</span>
          </div>
          <div className="flex gap-1">
            {EXAMPLE_MESSAGES.map((_, i) => (
              <button
                key={i}
                onClick={() => setMessageIndex(i)}
                className={`w-2 h-2 rounded-full transition-colors ${
                  i === messageIndex ? 'bg-brand' : 'bg-bg-elevated hover:bg-bg-hover'
                }`}
              />
            ))}
          </div>
        </div>

        {/* Pipeline Steps */}
        <div className="space-y-3">
          {/* Step 1: Padding */}
          <div className={`transition-all duration-300 ${activeStep >= 1 ? 'opacity-100' : 'opacity-40'}`}>
            <div className="flex items-center gap-2 mb-2">
              <span className="w-6 h-6 bg-brand rounded flex items-center justify-center text-white text-xs font-bold">1</span>
              <span className="font-medium text-white">Padding</span>
              <span className="text-xs text-text-muted">→ {pipeline.padded.length} bytes</span>
            </div>
            <div className="ml-8 bg-bg-elevated rounded-lg p-3">
              <div className="flex flex-wrap gap-1 font-mono text-[10px]">
                {Array.from(pipeline.padded).map((byte, i) => {
                  let colorClass = 'bg-bg-card text-text-muted';
                  if (i === 0) colorClass = 'bg-warning/20 text-warning';
                  else if (i < 3) colorClass = 'bg-brand/20 text-brand-light';
                  else if (i < 3 + pipeline.plaintextBytes.length) colorClass = 'bg-success/20 text-success';
                  return (
                    <span key={i} className={`px-1 py-0.5 rounded ${colorClass}`}>
                      {byte.toString(16).toUpperCase().padStart(2, '0')}
                    </span>
                  );
                })}
              </div>
              <div className="flex gap-4 mt-2 text-[10px] text-text-muted">
                <span><span className="inline-block w-2 h-2 bg-warning/30 rounded mr-1"></span>marker</span>
                <span><span className="inline-block w-2 h-2 bg-brand/30 rounded mr-1"></span>length</span>
                <span><span className="inline-block w-2 h-2 bg-success/30 rounded mr-1"></span>content</span>
                <span><span className="inline-block w-2 h-2 bg-bg-card rounded mr-1 border border-border"></span>padding</span>
              </div>
            </div>
          </div>

          {/* Arrow */}
          <div className={`ml-8 flex items-center gap-2 text-text-muted transition-opacity duration-300 ${activeStep >= 2 ? 'opacity-100' : 'opacity-20'}`}>
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
            </svg>
            <span className="text-xs">⊕ XOR with pad key</span>
          </div>

          {/* Step 2: Encryption */}
          <div className={`transition-all duration-300 ${activeStep >= 2 ? 'opacity-100' : 'opacity-40'}`}>
            <div className="flex items-center gap-2 mb-2">
              <span className="w-6 h-6 bg-brand rounded flex items-center justify-center text-white text-xs font-bold">2</span>
              <span className="font-medium text-white">OTP Encryption</span>
              <span className="text-xs text-text-muted">→ {pipeline.ciphertext.length} bytes ciphertext</span>
            </div>
            <div className="ml-8 bg-bg-elevated rounded-lg p-3 space-y-2">
              <div className="flex items-start gap-2 text-[10px] font-mono">
                <span className="text-text-muted w-16 shrink-0">Padded:</span>
                <span className="text-text-secondary break-all">{bytesToHex(pipeline.padded, 12)}...</span>
              </div>
              <div className="flex items-center gap-2 text-brand text-sm">
                <span className="w-16"></span>
                <span>⊕</span>
              </div>
              <div className="flex items-start gap-2 text-[10px] font-mono">
                <span className="text-text-muted w-16 shrink-0">Pad key:</span>
                <span className="text-success break-all">{bytesToHex(pipeline.encKey, 12)}...</span>
              </div>
              <div className="flex items-start gap-2 text-[10px] font-mono pt-2 border-t border-border">
                <span className="text-text-muted w-16 shrink-0">Cipher:</span>
                <span className="text-warning break-all">{bytesToHex(pipeline.ciphertext, 12)}...</span>
              </div>
            </div>
          </div>

          {/* Arrow */}
          <div className={`ml-8 flex items-center gap-2 text-text-muted transition-opacity duration-300 ${activeStep >= 3 ? 'opacity-100' : 'opacity-20'}`}>
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
            </svg>
            <span className="text-xs">Wegman-Carter MAC</span>
          </div>

          {/* Step 3: Authentication */}
          <div className={`transition-all duration-300 ${activeStep >= 3 ? 'opacity-100' : 'opacity-40'}`}>
            <div className="flex items-center gap-2 mb-2">
              <span className="w-6 h-6 bg-brand rounded flex items-center justify-center text-white text-xs font-bold">3</span>
              <span className="font-medium text-white">Authentication</span>
              <span className="text-xs text-text-muted">→ 32-byte tag</span>
            </div>
            <div className="ml-8 bg-bg-elevated rounded-lg p-3 space-y-2">
              <div className="text-[10px] text-text-muted mb-2">Auth key (64 bytes from pad):</div>
              <div className="flex flex-wrap gap-1 mb-2">
                <span className="px-2 py-1 bg-purple-500/20 text-purple-300 rounded text-[10px] font-mono">r₁: {bytesToHex(pipeline.authKey.slice(0, 16), 4)}...</span>
                <span className="px-2 py-1 bg-purple-500/20 text-purple-300 rounded text-[10px] font-mono">r₂: {bytesToHex(pipeline.authKey.slice(16, 32), 4)}...</span>
                <span className="px-2 py-1 bg-teal-500/20 text-teal-300 rounded text-[10px] font-mono">s₁: {bytesToHex(pipeline.authKey.slice(32, 48), 4)}...</span>
                <span className="px-2 py-1 bg-teal-500/20 text-teal-300 rounded text-[10px] font-mono">s₂: {bytesToHex(pipeline.authKey.slice(48, 64), 4)}...</span>
              </div>
              <div className="flex items-start gap-2 text-[10px] font-mono pt-2 border-t border-border">
                <span className="text-text-muted w-16 shrink-0">Tag:</span>
                <span className="text-success break-all">{bytesToHex(pipeline.tag)}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Final Output */}
        <div className={`bg-success/10 border border-success/30 rounded-lg p-4 transition-all duration-300 ${activeStep >= 3 ? 'opacity-100' : 'opacity-40'}`}>
          <div className="flex items-center gap-2 mb-2">
            <svg className="w-5 h-5 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
            </svg>
            <span className="font-medium text-success">Wire Format</span>
            <span className="text-xs text-text-muted ml-auto">
              {4 + pipeline.ciphertext.length + 32} bytes total
            </span>
          </div>
          <div className="flex flex-wrap gap-1 font-mono text-[10px]">
            <span className="px-2 py-1 bg-bg-elevated text-text-muted rounded">[header 4B]</span>
            <span className="px-2 py-1 bg-warning/20 text-warning rounded">[ciphertext {pipeline.ciphertext.length}B]</span>
            <span className="px-2 py-1 bg-success/20 text-success rounded">[tag 32B]</span>
          </div>
        </div>

        {/* Pad consumption note */}
        <div className="text-xs text-text-muted pt-3 border-t border-border">
          <strong className="text-white">Pad consumed:</strong> {AUTH_KEY_SIZE + pipeline.padded.length} bytes
          (64B auth key + {pipeline.padded.length}B encryption key)
        </div>
      </div>
    </div>
  );
}
