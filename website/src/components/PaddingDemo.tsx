/**
 * PaddingDemo - Interactive message padding demonstration
 *
 * Shows how ASH pads messages to minimum 32 bytes to prevent traffic analysis:
 * - Format: [0x00 marker][2-byte length BE][content][zero padding]
 * - All messages appear the same size on the network
 */
import { useState, useEffect } from 'react';

interface WasmModule {
  pad_message: (message: Uint8Array) => Uint8Array;
  unpad_message: (padded: Uint8Array) => Uint8Array;
  get_min_padded_size: () => number;
  default: () => Promise<void>;
}

function bytesToHex(byte: number): string {
  return byte.toString(16).toUpperCase().padStart(2, '0');
}

export default function PaddingDemo() {
  const [wasmModule, setWasmModule] = useState<WasmModule | null>(null);
  const [wasmReady, setWasmReady] = useState(false);
  const [message, setMessage] = useState('hi');
  const [padded, setPadded] = useState<Uint8Array | null>(null);
  const [unpadded, setUnpadded] = useState<string | null>(null);
  const [minPaddedSize, setMinPaddedSize] = useState(32);

  // Initialize WASM
  useEffect(() => {
    async function initWasm() {
      try {
        const importFn = new Function('url', 'return import(url)');
        const module = await importFn('/wasm/ash_wasm.js') as WasmModule;
        await module.default();
        setWasmModule(module);
        setWasmReady(true);
        setMinPaddedSize(module.get_min_padded_size());
      } catch (e) {
        console.warn('WASM init failed:', e);
      }
    }
    initWasm();
  }, []);

  // Pad message when it changes
  useEffect(() => {
    if (!wasmReady || !wasmModule) return;

    try {
      const encoder = new TextEncoder();
      const decoder = new TextDecoder();
      const messageBytes = encoder.encode(message);

      const paddedBytes = wasmModule.pad_message(messageBytes);
      setPadded(paddedBytes);

      const unpaddedBytes = wasmModule.unpad_message(paddedBytes);
      setUnpadded(decoder.decode(unpaddedBytes));
    } catch (e) {
      console.error('Padding error:', e);
    }
  }, [message, wasmModule, wasmReady]);

  const encoder = new TextEncoder();
  const messageBytes = encoder.encode(message);

  return (
    <div className="bg-bg-card border border-border rounded-2xl overflow-hidden">
      <div className="px-4 py-3 border-b border-border bg-bg-elevated flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-success animate-pulse"></div>
          <h3 className="font-semibold text-white">Live Padding Demo</h3>
        </div>
        <span className="text-xs text-text-muted px-2 py-1 bg-brand/20 text-brand-light rounded">
          {wasmReady ? 'Rust WASM' : 'Loading...'}
        </span>
      </div>

      <div className="p-5 space-y-6">
        {/* Message Input */}
        <div>
          <label className="block text-sm font-medium text-text-secondary mb-2">
            Original message
          </label>
          <input
            type="text"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Type a short message..."
            maxLength={50}
            className="w-full bg-bg-elevated border border-border rounded-lg px-4 py-2.5 text-white font-mono focus:outline-none focus:border-brand"
          />
          <p className="text-xs text-text-muted mt-1">
            {messageBytes.length} byte{messageBytes.length !== 1 ? 's' : ''} input
          </p>
        </div>

        {/* Padding Visualization */}
        {padded && (
          <div className="bg-bg-elevated rounded-xl p-5 space-y-4">
            <div className="text-sm font-medium text-white mb-3">
              Padded output: {padded.length} bytes (minimum {minPaddedSize})
            </div>

            {/* Byte visualization */}
            <div className="flex flex-wrap gap-1 font-mono text-xs">
              {Array.from(padded).map((byte, i) => {
                let colorClass = 'bg-bg-card text-text-muted'; // zero padding
                let label = '';

                if (i === 0) {
                  colorClass = 'bg-warning/20 text-warning';
                  label = 'marker';
                } else if (i === 1 || i === 2) {
                  colorClass = 'bg-brand/20 text-brand-light';
                  label = i === 1 ? 'len hi' : 'len lo';
                } else if (i < 3 + messageBytes.length) {
                  colorClass = 'bg-success/20 text-success';
                  label = 'content';
                } else {
                  label = 'pad';
                }

                return (
                  <div
                    key={i}
                    className={`flex flex-col items-center`}
                    title={`Byte ${i}: ${label}`}
                  >
                    <span className={`px-1.5 py-1 rounded text-[10px] ${colorClass}`}>
                      {bytesToHex(byte)}
                    </span>
                  </div>
                );
              })}
            </div>

            {/* Legend */}
            <div className="flex flex-wrap gap-4 text-xs text-text-muted pt-3 border-t border-border">
              <div className="flex items-center gap-1">
                <span className="w-3 h-3 bg-warning/20 rounded"></span>
                <span>0x00 marker</span>
              </div>
              <div className="flex items-center gap-1">
                <span className="w-3 h-3 bg-brand/20 rounded"></span>
                <span>Length ({messageBytes.length})</span>
              </div>
              <div className="flex items-center gap-1">
                <span className="w-3 h-3 bg-success/20 rounded"></span>
                <span>Content</span>
              </div>
              <div className="flex items-center gap-1">
                <span className="w-3 h-3 bg-bg-card border border-border rounded"></span>
                <span>Zero padding</span>
              </div>
            </div>

            {/* Format breakdown */}
            <div className="mt-4 space-y-2 text-sm">
              <div className="flex items-center gap-3">
                <span className="text-text-muted w-32">Byte 0:</span>
                <code className="text-warning">0x00</code>
                <span className="text-text-secondary">— padding marker</span>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-text-muted w-32">Bytes 1-2:</span>
                <code className="text-brand-light">
                  {bytesToHex(padded[1])} {bytesToHex(padded[2])}
                </code>
                <span className="text-text-secondary">
                  — length = {(padded[1] << 8) | padded[2]} (big-endian)
                </span>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-text-muted w-32">Bytes 3-{2 + messageBytes.length}:</span>
                <code className="text-success">
                  {Array.from(messageBytes.slice(0, 4)).map(b => bytesToHex(b)).join(' ')}
                  {messageBytes.length > 4 ? '...' : ''}
                </code>
                <span className="text-text-secondary">— "{message.slice(0, 10)}{message.length > 10 ? '...' : ''}"</span>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-text-muted w-32">Bytes {3 + messageBytes.length}-{padded.length - 1}:</span>
                <code className="text-text-muted">00 00 00...</code>
                <span className="text-text-secondary">— zero padding ({padded.length - 3 - messageBytes.length} bytes)</span>
              </div>
            </div>
          </div>
        )}

        {/* Traffic Analysis Comparison */}
        <div className="bg-bg-elevated rounded-lg p-4">
          <div className="text-sm font-medium text-white mb-3">Traffic Analysis Protection</div>
          <div className="space-y-2 text-xs">
            <div className="flex items-center gap-3">
              <span className="text-text-muted w-32">Without padding:</span>
              <div className="flex-1 flex items-center gap-2">
                <div className="h-4 bg-danger/30 rounded" style={{ width: `${Math.max(20, messageBytes.length * 5)}px` }}></div>
                <span className="text-text-secondary">{messageBytes.length} bytes — distinguishable!</span>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-text-muted w-32">With padding:</span>
              <div className="flex-1 flex items-center gap-2">
                <div className="h-4 bg-success/30 rounded" style={{ width: `${Math.max(padded?.length ?? minPaddedSize, minPaddedSize) * 5}px` }}></div>
                <span className="text-text-secondary">{padded?.length ?? minPaddedSize} bytes — all messages same size</span>
              </div>
            </div>
          </div>
        </div>

        {/* Unpadding Result */}
        {unpadded !== null && (
          <div className="bg-success/10 border border-success/30 rounded-lg p-4">
            <div className="flex items-center gap-2 mb-2">
              <svg className="w-4 h-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
              <span className="text-sm font-medium text-success">Unpadded (receiver side):</span>
            </div>
            <code className="text-white font-mono">"{unpadded}"</code>
            <span className="text-text-muted text-xs ml-2">({unpadded.length} bytes)</span>
          </div>
        )}

        {/* Explanation */}
        <div className="text-xs text-text-muted border-t border-border pt-4">
          <p>
            <strong className="text-white">Why padding matters:</strong> Without padding, an attacker
            could fingerprint messages by size. "yes" (3 bytes) vs "no" (2 bytes) would be distinguishable
            even when encrypted. With minimum 32-byte padding, all short messages look identical.
          </p>
        </div>
      </div>
    </div>
  );
}
