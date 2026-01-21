/* tslint:disable */
/* eslint-disable */

/**
 * Convert bytes to hex string (for display).
 */
export function bytes_to_hex(bytes: Uint8Array): string;

/**
 * Compute 256-bit Wegman-Carter authentication tag.
 *
 * # Arguments
 * * `auth_key` - 64 bytes from pad (r1 || r2 || s1 || s2)
 * * `header` - Frame header bytes
 * * `ciphertext` - Encrypted payload
 *
 * # Returns
 * 32-byte authentication tag.
 */
export function compute_auth_tag(auth_key: Uint8Array, header: Uint8Array, ciphertext: Uint8Array): Uint8Array;

/**
 * Get the authentication key size (64 bytes).
 */
export function get_auth_key_size(): number;

/**
 * Get the minimum padded message size (32 bytes).
 */
export function get_min_padded_size(): number;

/**
 * Get the authentication tag size (32 bytes).
 */
export function get_tag_size(): number;

/**
 * Convert hex string to bytes.
 */
export function hex_to_bytes(hex: string): Uint8Array;

/**
 * OTP decrypt: XOR ciphertext with key bytes.
 *
 * Since XOR is symmetric, this is the same operation as encrypt.
 */
export function otp_decrypt(key: Uint8Array, ciphertext: Uint8Array): Uint8Array;

/**
 * OTP encrypt: XOR plaintext with key bytes.
 *
 * # Arguments
 * * `key` - Key bytes (must equal plaintext length)
 * * `plaintext` - Data to encrypt
 *
 * # Returns
 * Ciphertext bytes, or throws on length mismatch.
 */
export function otp_encrypt(key: Uint8Array, plaintext: Uint8Array): Uint8Array;

/**
 * Pad a message to minimum 32 bytes.
 *
 * Format: [0x00 marker][2-byte length BE][content][zero padding]
 *
 * # Arguments
 * * `message` - Original message bytes
 *
 * # Returns
 * Padded message (minimum 32 bytes).
 */
export function pad_message(message: Uint8Array): Uint8Array;

/**
 * Remove padding from a message.
 *
 * # Arguments
 * * `padded` - Padded message bytes
 *
 * # Returns
 * Original message bytes.
 */
export function unpad_message(padded: Uint8Array): Uint8Array;

/**
 * Verify 256-bit Wegman-Carter authentication tag.
 *
 * # Arguments
 * * `auth_key` - 64 bytes from pad
 * * `header` - Frame header bytes
 * * `ciphertext` - Encrypted payload
 * * `tag` - 32-byte tag to verify
 *
 * # Returns
 * true if valid, false otherwise.
 */
export function verify_auth_tag(auth_key: Uint8Array, header: Uint8Array, ciphertext: Uint8Array, tag: Uint8Array): boolean;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly otp_encrypt: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly otp_decrypt: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly compute_auth_tag: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
    readonly verify_auth_tag: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => [number, number, number];
    readonly pad_message: (a: number, b: number) => [number, number, number, number];
    readonly unpad_message: (a: number, b: number) => [number, number, number, number];
    readonly get_min_padded_size: () => number;
    readonly get_auth_key_size: () => number;
    readonly bytes_to_hex: (a: number, b: number) => [number, number];
    readonly hex_to_bytes: (a: number, b: number) => [number, number, number, number];
    readonly get_tag_size: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
