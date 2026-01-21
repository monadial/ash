/**
 * ProtocolDemo - Interactive ASH Protocol demonstration using React
 *
 * This component demonstrates the full ASH protocol including:
 * - Bidirectional pad consumption (Alice from start, Bob from end)
 * - Wegman-Carter 256-bit authentication (64-byte auth keys)
 * - Message padding to minimum 32 bytes
 * - Real OTP encryption via WASM when available
 *
 * Uses the ASH Core Rust library compiled to WebAssembly.
 */
import { useState, useEffect, useCallback, useRef } from 'react';

// Constants matching the Rust core
const PAD_SIZE = 1024;
const AUTH_KEY_SIZE = 64;  // Wegman-Carter: r1(16) + r2(16) + s1(16) + s2(16)
const MIN_PADDED_SIZE = 32;
const TAG_SIZE = 32;
const FRAME_HEADER = new Uint8Array([0x01, 0x01, 0x00, 0x20]); // version=1, type=text, length=32

interface WasmModule {
  pad_message: (plaintext: Uint8Array) => Uint8Array;
  unpad_message: (padded: Uint8Array) => Uint8Array;
  otp_encrypt: (key: Uint8Array, plaintext: Uint8Array) => Uint8Array;
  otp_decrypt: (key: Uint8Array, ciphertext: Uint8Array) => Uint8Array;
  compute_auth_tag: (authKey: Uint8Array, header: Uint8Array, ciphertext: Uint8Array) => Uint8Array;
  verify_auth_tag: (authKey: Uint8Array, header: Uint8Array, ciphertext: Uint8Array, tag: Uint8Array) => boolean;
  bytes_to_hex: (bytes: Uint8Array) => string;
  hex_to_bytes: (hex: string) => Uint8Array;
  get_auth_key_size: () => number;
  get_tag_size: () => number;
  get_min_padded_size: () => number;
  generate_mnemonic: (padBytes: Uint8Array) => string;
  default: () => Promise<void>;
}

interface MessageResult {
  ciphertextHex: string;
  tagHex: string;
  bytesUsed: number;
  authBytes: number;
  encBytes: number;
  verified?: boolean;
}

interface Message {
  id: number;
  plaintext: string;
  result: MessageResult;
  sender: 'alice' | 'bob';
}

interface MessageSize {
  auth: number;
  enc: number;
}

interface PadState {
  bytes: Uint8Array;
  aliceConsumed: number;
  bobConsumed: number;
  aliceAuthConsumed: number;
  aliceEncConsumed: number;
  bobAuthConsumed: number;
  bobEncConsumed: number;
  aliceMsgCount: number;
  bobMsgCount: number;
  // Track individual message sizes for progress bar visualization
  aliceMessageSizes: MessageSize[];
  bobMessageSizes: MessageSize[];
}

// Utility functions
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).toUpperCase().padStart(2, '0')).join('');
}

function generatePad(): Uint8Array {
  const bytes = new Uint8Array(PAD_SIZE);
  crypto.getRandomValues(bytes);
  return bytes;
}

// JS fallback functions for when WASM isn't available
function jsPadMessage(plaintext: Uint8Array, targetSize?: number): Uint8Array {
  const size = targetSize ?? Math.max(MIN_PADDED_SIZE, 3 + plaintext.length);
  const padded = new Uint8Array(size);
  padded[0] = 0x00; // marker
  padded[1] = (plaintext.length >> 8) & 0xff;
  padded[2] = plaintext.length & 0xff;
  padded.set(plaintext, 3);
  return padded;
}

function jsXor(key: Uint8Array, data: Uint8Array): Uint8Array {
  const result = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) {
    result[i] = key[i] ^ data[i];
  }
  return result;
}

function jsFakeTag(authKey: Uint8Array): Uint8Array {
  // Simple fallback - not cryptographically secure, just for demo
  const tag = new Uint8Array(TAG_SIZE);
  for (let i = 0; i < TAG_SIZE; i++) {
    tag[i] = authKey[i] ^ authKey[i + 32];
  }
  return tag;
}

export default function ProtocolDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [padState, setPadState] = useState<PadState>(() => ({
    bytes: generatePad(),
    aliceConsumed: 0,
    bobConsumed: 0,
    aliceAuthConsumed: 0,
    aliceEncConsumed: 0,
    bobAuthConsumed: 0,
    bobEncConsumed: 0,
    aliceMsgCount: 0,
    bobMsgCount: 0,
    aliceMessageSizes: [],
    bobMessageSizes: [],
  }));
  const [aliceMessages, setAliceMessages] = useState<Message[]>([]);
  const [bobMessages, setBobMessages] = useState<Message[]>([]);
  const [aliceInput, setAliceInput] = useState('');
  const [bobInput, setBobInput] = useState('');
  const [messageIdCounter, setMessageIdCounter] = useState(0);
  const [mnemonic, setMnemonic] = useState<string[]>([]);

  const aliceMessagesRef = useRef<HTMLDivElement>(null);
  const bobMessagesRef = useRef<HTMLDivElement>(null);

  // Initialize WASM module at runtime
  useEffect(() => {
    async function initWasm() {
      try {
        // Check if module is already loaded (e.g., from a previous mount)
        if ((window as any).__ashWasmModule) {
          setWasmModule((window as any).__ashWasmModule);
          setWasmReady(true);
          console.log('ASH Core WASM already initialized');
          return;
        }

        // Dynamic import from public folder - use Function to avoid Vite analysis
        const importFn = new Function('url', 'return import(url)');
        const module = await importFn('/wasm/ash_wasm.js') as WasmModule;
        await module.default();

        // Cache for potential re-mounts
        (window as any).__ashWasmModule = module;

        setWasmModule(module);
        setWasmReady(true);
        console.log('ASH Core WASM initialized - Full protocol enabled');
      } catch (e) {
        console.warn('WASM init failed, using JS fallback:', e);
      }
    }
    initWasm();
  }, []);

  // Generate mnemonic when pad or WASM changes
  useEffect(() => {
    if (wasmReady && wasmModule) {
      const words = wasmModule.generate_mnemonic(padState.bytes);
      setMnemonic(words.split(' '));
    } else {
      // Fallback: use first bytes as simple words (demo only)
      const fallbackWords = ['pad', 'not', 'verified', 'yet', 'load', 'wasm'];
      setMnemonic(fallbackWords);
    }
  }, [padState.bytes, wasmModule, wasmReady]);

  // Scroll to bottom when messages change
  useEffect(() => {
    aliceMessagesRef.current?.scrollTo({ top: aliceMessagesRef.current.scrollHeight, behavior: 'smooth' });
  }, [aliceMessages]);

  useEffect(() => {
    bobMessagesRef.current?.scrollTo({ top: bobMessagesRef.current.scrollHeight, behavior: 'smooth' });
  }, [bobMessages]);

  // Process a message with full authentication
  const processMessage = useCallback((plaintext: string, isAlice: boolean): MessageResult | { error: string } => {
    const encoder = new TextEncoder();
    const plaintextBytes = encoder.encode(plaintext);

    // Calculate padded size: 3-byte header + content, minimum 32 bytes
    const paddedSize = Math.max(MIN_PADDED_SIZE, 3 + plaintextBytes.length);
    const bytesNeeded = AUTH_KEY_SIZE + paddedSize;
    const remaining = PAD_SIZE - padState.aliceConsumed - padState.bobConsumed;

    if (bytesNeeded > remaining) {
      return { error: `Not enough pad bytes! Need ${bytesNeeded}, only ${remaining} remaining.` };
    }

    let authKey: Uint8Array, encKey: Uint8Array;

    if (isAlice) {
      // Alice consumes from start: [auth_key 64][enc_key N]
      const authKeyStart = padState.aliceConsumed;
      authKey = padState.bytes.slice(authKeyStart, authKeyStart + AUTH_KEY_SIZE);
      const encKeyStart = authKeyStart + AUTH_KEY_SIZE;
      encKey = padState.bytes.slice(encKeyStart, encKeyStart + paddedSize);
    } else {
      // Bob consumes from end: [auth_key 64][enc_key N]
      const authKeyStart = PAD_SIZE - padState.bobConsumed - AUTH_KEY_SIZE;
      authKey = padState.bytes.slice(authKeyStart, authKeyStart + AUTH_KEY_SIZE);
      const encKeyStart = authKeyStart - paddedSize;
      encKey = padState.bytes.slice(encKeyStart, encKeyStart + paddedSize);
    }

    let ciphertextHex: string, tagHex: string, verified: boolean;

    if (wasmReady && wasmModule) {
      // Use actual Rust core for full protocol
      const padded = wasmModule.pad_message(plaintextBytes);
      const ciphertext = wasmModule.otp_encrypt(encKey, padded);
      const tag = wasmModule.compute_auth_tag(authKey, FRAME_HEADER, ciphertext);

      ciphertextHex = wasmModule.bytes_to_hex(ciphertext);
      tagHex = wasmModule.bytes_to_hex(tag);

      // Verify the tag (simulating receiver verification)
      verified = wasmModule.verify_auth_tag(authKey, FRAME_HEADER, ciphertext, tag);
    } else {
      // JS fallback - pad to calculated size
      const padded = jsPadMessage(plaintextBytes, paddedSize);
      const ciphertext = jsXor(encKey, padded);
      const tag = jsFakeTag(authKey);

      ciphertextHex = bytesToHex(ciphertext);
      tagHex = bytesToHex(tag);
      verified = true; // JS fallback always "verifies"
    }

    // Update pad state
    setPadState(prev => {
      if (isAlice) {
        return {
          ...prev,
          aliceConsumed: prev.aliceConsumed + bytesNeeded,
          aliceAuthConsumed: prev.aliceAuthConsumed + AUTH_KEY_SIZE,
          aliceEncConsumed: prev.aliceEncConsumed + paddedSize,
          aliceMsgCount: prev.aliceMsgCount + 1,
          aliceMessageSizes: [...prev.aliceMessageSizes, { auth: AUTH_KEY_SIZE, enc: paddedSize }],
        };
      } else {
        return {
          ...prev,
          bobConsumed: prev.bobConsumed + bytesNeeded,
          bobAuthConsumed: prev.bobAuthConsumed + AUTH_KEY_SIZE,
          bobEncConsumed: prev.bobEncConsumed + paddedSize,
          bobMsgCount: prev.bobMsgCount + 1,
          bobMessageSizes: [...prev.bobMessageSizes, { auth: AUTH_KEY_SIZE, enc: paddedSize }],
        };
      }
    });

    return {
      ciphertextHex,
      tagHex,
      bytesUsed: bytesNeeded,
      authBytes: AUTH_KEY_SIZE,
      encBytes: paddedSize,
      verified,
    };
  }, [padState, wasmModule, wasmReady]);

  const sendAliceMessage = useCallback(() => {
    const text = aliceInput.trim();
    if (!text) return;

    const result = processMessage(text, true);
    if ('error' in result) {
      alert(result.error);
      return;
    }

    setAliceMessages(prev => [...prev, {
      id: messageIdCounter,
      plaintext: text,
      result,
      sender: 'alice',
    }]);
    setMessageIdCounter(prev => prev + 1);
    setAliceInput('');
  }, [aliceInput, messageIdCounter, processMessage]);

  const sendBobMessage = useCallback(() => {
    const text = bobInput.trim();
    if (!text) return;

    const result = processMessage(text, false);
    if ('error' in result) {
      alert(result.error);
      return;
    }

    setBobMessages(prev => [...prev, {
      id: messageIdCounter,
      plaintext: text,
      result,
      sender: 'bob',
    }]);
    setMessageIdCounter(prev => prev + 1);
    setBobInput('');
  }, [bobInput, messageIdCounter, processMessage]);

  const resetDemo = useCallback(() => {
    setPadState({
      bytes: generatePad(),
      aliceConsumed: 0,
      bobConsumed: 0,
      aliceAuthConsumed: 0,
      aliceEncConsumed: 0,
      bobAuthConsumed: 0,
      bobEncConsumed: 0,
      aliceMsgCount: 0,
      bobMsgCount: 0,
      aliceMessageSizes: [],
      bobMessageSizes: [],
    });
    setAliceMessages([]);
    setBobMessages([]);
    setAliceInput('');
    setBobInput('');
    setMessageIdCounter(0);
  }, []);

  // Calculations
  const remaining = PAD_SIZE - padState.aliceConsumed - padState.bobConsumed;
  const minMsgSize = AUTH_KEY_SIZE + MIN_PADDED_SIZE;
  const possibleMessages = Math.floor(remaining / minMsgSize);

  return (
    <div className="bg-bg-card border border-border rounded-2xl p-6 lg:p-8">
      {/* Pad Visualization Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="font-semibold text-lg">Shared One-Time Pad</h3>
          <p className="text-text-muted text-sm">
            1 KB pad • Each message: {AUTH_KEY_SIZE}B auth + {MIN_PADDED_SIZE}B min encrypted
          </p>
        </div>
        <button
          onClick={resetDemo}
          className="text-xs text-brand hover:text-brand-light transition-colors flex items-center gap-1.5 px-3 py-1.5 border border-brand/30 rounded-lg hover:bg-brand-subtle"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          Reset Demo
        </button>
      </div>

      {/* Mnemonic Verification */}
      <div className="bg-success/10 border border-success/30 rounded-xl p-4 mb-6">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <svg className="w-5 h-5 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
            </svg>
            <span className="font-medium text-success">Mnemonic Verification</span>
          </div>
          <span className="text-xs text-text-muted">
            {wasmReady ? 'Computed via Rust FFI' : 'Loading...'}
          </span>
        </div>
        <p className="text-xs text-text-secondary mb-3">
          Both Alice and Bob see identical words — verbal confirmation that pads match:
        </p>
        <div className="flex flex-wrap gap-2">
          {mnemonic.map((word, i) => (
            <span key={i} className="px-3 py-1.5 bg-bg-elevated rounded-lg text-white font-medium">
              {word}
            </span>
          ))}
        </div>
        <div className="flex items-center gap-4 mt-3 pt-3 border-t border-success/20">
          <div className="flex items-center gap-2 text-xs">
            <div className="w-6 h-6 rounded-full bg-brand flex items-center justify-center text-white text-[10px] font-bold">A</div>
            <span className="text-text-muted">Alice sees: <span className="text-success">{mnemonic.join(' ')}</span></span>
          </div>
          <div className="flex items-center gap-2 text-xs">
            <div className="w-6 h-6 rounded-full bg-success flex items-center justify-center text-white text-[10px] font-bold">B</div>
            <span className="text-text-muted">Bob sees: <span className="text-success">{mnemonic.join(' ')}</span></span>
          </div>
        </div>
      </div>

      {/* Pad Progress Bar */}
      <div className="bg-bg-elevated rounded-xl p-4 mb-8">
        {/* Main progress bar */}
        <div className="relative h-10 bg-bg-hover rounded-lg overflow-hidden mb-3">
          <div className="absolute inset-0 flex">
            {/* Alice's messages (from left): each message is [auth][enc] - flattened */}
            {padState.aliceMessageSizes.flatMap((msg, i) => [
              <div
                key={`alice-auth-${i}`}
                className="bg-purple-500 h-full transition-all duration-300"
                style={{ width: `${(msg.auth / PAD_SIZE) * 100}%` }}
                title={`Alice msg ${i + 1}: Auth (${msg.auth}B)`}
              />,
              <div
                key={`alice-enc-${i}`}
                className="bg-brand h-full transition-all duration-300"
                style={{ width: `${(msg.enc / PAD_SIZE) * 100}%` }}
                title={`Alice msg ${i + 1}: Enc (${msg.enc}B)`}
              />
            ])}

            {/* Available space (middle) */}
            {remaining > 0 && (
              <div
                key="available"
                className="bg-bg-hover/30 h-full flex-1 transition-all duration-300"
                title={`Available: ${remaining} bytes`}
              />
            )}

            {/* Bob's messages (from right): displayed as [enc][auth] - flattened */}
            {padState.bobMessageSizes.slice().reverse().flatMap((msg, i) => {
              const origIndex = padState.bobMessageSizes.length - 1 - i;
              return [
                <div
                  key={`bob-enc-${origIndex}`}
                  className="bg-success h-full transition-all duration-300"
                  style={{ width: `${(msg.enc / PAD_SIZE) * 100}%` }}
                  title={`Bob msg ${origIndex + 1}: Enc (${msg.enc}B)`}
                />,
                <div
                  key={`bob-auth-${origIndex}`}
                  className="bg-teal-500 h-full transition-all duration-300"
                  style={{ width: `${(msg.auth / PAD_SIZE) * 100}%` }}
                  title={`Bob msg ${origIndex + 1}: Auth (${msg.auth}B)`}
                />
              ];
            })}
          </div>

          {/* Center label */}
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <span className="text-xs font-medium text-text-muted bg-bg-elevated/80 px-2 py-0.5 rounded">
              {remaining > 0 ? `${remaining}B available` : 'Pad exhausted!'}
            </span>
          </div>
        </div>

        {/* Byte markers */}
        <div className="flex justify-between text-[10px] text-text-muted font-mono mb-4">
          <span>0</span>
          <span>256</span>
          <span>512</span>
          <span>768</span>
          <span>1024</span>
        </div>

        {/* Extended breakdown */}
        <div className="grid grid-cols-3 gap-4 text-center">
          {/* Alice breakdown */}
          <div className="bg-bg-subtle rounded-lg p-3">
            <div className="flex items-center justify-center gap-2 mb-2">
              <div className="w-6 h-6 rounded-full bg-brand flex items-center justify-center text-white text-xs font-bold">A</div>
              <span className="text-sm font-medium">Alice</span>
            </div>
            {padState.aliceConsumed > 0 ? (
              <div className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-purple-400">{padState.aliceAuthConsumed}B auth</span>
                  <span className="text-brand-light">{padState.aliceEncConsumed}B enc</span>
                </div>
                <div className="text-[10px] text-text-muted">
                  {padState.aliceMsgCount} message{padState.aliceMsgCount !== 1 ? 's' : ''} • {padState.aliceConsumed}B total
                </div>
              </div>
            ) : (
              <div className="text-xs text-text-muted">No messages sent</div>
            )}
          </div>

          {/* Available */}
          <div className="bg-bg-subtle rounded-lg p-3">
            <div className="text-2xl font-bold text-white mb-1">{remaining}</div>
            <div className="text-xs text-text-muted">bytes available</div>
            <div className="text-[10px] text-text-muted mt-1">
              ~{possibleMessages} message{possibleMessages !== 1 ? 's' : ''} possible
            </div>
          </div>

          {/* Bob breakdown */}
          <div className="bg-bg-subtle rounded-lg p-3">
            <div className="flex items-center justify-center gap-2 mb-2">
              <span className="text-sm font-medium">Bob</span>
              <div className="w-6 h-6 rounded-full bg-success flex items-center justify-center text-white text-xs font-bold">B</div>
            </div>
            {padState.bobConsumed > 0 ? (
              <div className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-success">{padState.bobEncConsumed}B enc</span>
                  <span className="text-teal-400">{padState.bobAuthConsumed}B auth</span>
                </div>
                <div className="text-[10px] text-text-muted">
                  {padState.bobMsgCount} message{padState.bobMsgCount !== 1 ? 's' : ''} • {padState.bobConsumed}B total
                </div>
              </div>
            ) : (
              <div className="text-xs text-text-muted">No messages sent</div>
            )}
          </div>
        </div>

        {/* Legend */}
        <div className="flex flex-wrap justify-center gap-4 mt-4 pt-4 border-t border-border text-xs text-text-muted">
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-purple-500"></div>
            <span>Alice auth ({AUTH_KEY_SIZE}B)</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-brand"></div>
            <span>Alice enc (variable)</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-bg-hover border border-border"></div>
            <span>Available</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-success"></div>
            <span>Bob enc (variable)</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-teal-500"></div>
            <span>Bob auth ({AUTH_KEY_SIZE}B)</span>
          </div>
        </div>
      </div>

      {/* Two-column conversation */}
      <div className="grid md:grid-cols-2 gap-6 mb-8">
        {/* Alice's Side */}
        <div className="bg-bg-subtle border border-border rounded-xl p-5">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-full bg-brand flex items-center justify-center text-white font-bold">A</div>
            <div>
              <h4 className="font-semibold">Alice (Initiator)</h4>
              <p className="text-text-muted text-xs">Encrypts from pad start →</p>
            </div>
          </div>
          <div className="mb-4">
            <label htmlFor="alice-input" className="block text-xs text-text-muted mb-2">Send a message</label>
            <div className="flex gap-2">
              <input
                type="text"
                id="alice-input"
                maxLength={128}
                value={aliceInput}
                onChange={(e) => setAliceInput(e.target.value)}
                onKeyPress={(e) => e.key === 'Enter' && sendAliceMessage()}
                placeholder="Type your message..."
                className="flex-1 bg-bg-elevated border border-border rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:border-brand"
              />
              <button
                onClick={sendAliceMessage}
                className="px-4 py-2 bg-brand text-white text-sm font-medium rounded-lg hover:bg-brand-light transition-colors"
              >
                Send
              </button>
            </div>
          </div>
          <div ref={aliceMessagesRef} className="space-y-3 max-h-48 overflow-y-auto">
            {aliceMessages.map((msg) => (
              <MessageCard key={msg.id} message={msg} wasmReady={wasmReady} />
            ))}
          </div>
        </div>

        {/* Bob's Side */}
        <div className="bg-bg-subtle border border-border rounded-xl p-5">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-full bg-success flex items-center justify-center text-white font-bold">B</div>
            <div>
              <h4 className="font-semibold">Bob (Responder)</h4>
              <p className="text-text-muted text-xs">← Encrypts from pad end</p>
            </div>
          </div>
          <div className="mb-4">
            <label htmlFor="bob-input" className="block text-xs text-text-muted mb-2">Send a message</label>
            <div className="flex gap-2">
              <input
                type="text"
                id="bob-input"
                maxLength={128}
                value={bobInput}
                onChange={(e) => setBobInput(e.target.value)}
                onKeyPress={(e) => e.key === 'Enter' && sendBobMessage()}
                placeholder="Type your message..."
                className="flex-1 bg-bg-elevated border border-border rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:border-brand"
              />
              <button
                onClick={sendBobMessage}
                className="px-4 py-2 bg-success text-white text-sm font-medium rounded-lg hover:brightness-110 transition-all"
              >
                Send
              </button>
            </div>
          </div>
          <div ref={bobMessagesRef} className="space-y-3 max-h-48 overflow-y-auto">
            {bobMessages.map((msg) => (
              <MessageCard key={msg.id} message={msg} wasmReady={wasmReady} />
            ))}
          </div>
        </div>
      </div>

      {/* How it works */}
      <div className="mt-8 pt-6 border-t border-border">
        <h4 className="font-semibold mb-4">How authenticated encryption works</h4>
        <div className="grid md:grid-cols-3 gap-6 text-sm text-text-secondary">
          <div>
            <div className="w-8 h-8 rounded-lg bg-brand-subtle flex items-center justify-center mb-2">
              <span className="text-brand font-bold">1</span>
            </div>
            <p>
              <strong className="text-white">Authentication key (64B).</strong> Each message uses a 64-byte
              Wegman-Carter authentication key for a 256-bit MAC. This ensures message integrity —
              any tampering is detected.
            </p>
          </div>
          <div>
            <div className="w-8 h-8 rounded-lg bg-brand-subtle flex items-center justify-center mb-2">
              <span className="text-brand font-bold">2</span>
            </div>
            <p>
              <strong className="text-white">Encryption key (32B).</strong> The message is padded to
              32 bytes minimum, then XOR'd with unique pad bytes. OTP encryption is mathematically
              unbreakable when keys are truly random and never reused.
            </p>
          </div>
          <div>
            <div className="w-8 h-8 rounded-lg bg-brand-subtle flex items-center justify-center mb-2">
              <span className="text-brand font-bold">3</span>
            </div>
            <p>
              <strong className="text-white">Verify-then-decrypt.</strong> Receivers verify the MAC
              before decryption. If the tag doesn't match, the message is rejected — preventing
              any oracle attacks on the ciphertext.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

// Message card component
function MessageCard({ message, wasmReady }: { message: Message; wasmReady: boolean }) {
  const isAlice = message.sender === 'alice';
  const shortCipher = message.result.ciphertextHex.substring(0, 24) + '...';
  const shortTag = message.result.tagHex.substring(0, 24) + '...';

  return (
    <div className="text-xs animate-fade-in">
      <div className={isAlice ? 'bg-brand/20 rounded-lg p-2' : 'bg-success/20 rounded-lg p-2'}>
        <div className="text-white mb-1 font-medium">"{message.plaintext}"</div>
        <div className="font-mono text-text-muted text-[10px] break-all">
          <span className="text-warning">ct:</span> {shortCipher}
        </div>
        <div className="font-mono text-text-muted text-[10px] break-all">
          <span className={isAlice ? 'text-purple-400' : 'text-teal-400'}>tag:</span> {shortTag}
        </div>
        <div className="text-text-muted text-[10px] mt-1 flex items-center gap-2 flex-wrap">
          {message.result.bytesUsed}B ({message.result.authBytes}B auth + {message.result.encBytes}B enc)
          {wasmReady ? (
            <span className="px-1 py-0.5 bg-brand/30 text-brand-light rounded text-[9px]">
              Rust {message.result.verified && '✓'}
            </span>
          ) : (
            <span className="px-1 py-0.5 bg-warning/30 text-warning rounded text-[9px]">JS</span>
          )}
        </div>
      </div>
    </div>
  );
}
