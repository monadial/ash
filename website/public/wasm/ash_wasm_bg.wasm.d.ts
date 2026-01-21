/* tslint:disable */
/* eslint-disable */
export const memory: WebAssembly.Memory;
export const otp_decrypt: (a: number, b: number, c: number, d: number) => [number, number, number, number];
export const compute_auth_tag: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
export const verify_auth_tag: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => [number, number, number];
export const pad_message: (a: number, b: number) => [number, number, number, number];
export const unpad_message: (a: number, b: number) => [number, number, number, number];
export const get_min_padded_size: () => number;
export const get_auth_key_size: () => number;
export const bytes_to_hex: (a: number, b: number) => [number, number];
export const hex_to_bytes: (a: number, b: number) => [number, number, number, number];
export const generate_mnemonic: (a: number, b: number) => [number, number];
export const generate_mnemonic_n: (a: number, b: number, c: number) => [number, number];
export const get_min_pad_size_for_tokens: () => number;
export const derive_conversation_id: (a: number, b: number) => [number, number, number, number];
export const derive_auth_token: (a: number, b: number) => [number, number, number, number];
export const derive_burn_token: (a: number, b: number) => [number, number, number, number];
export const compute_crc32: (a: number, b: number) => number;
export const verify_crc32: (a: number, b: number, c: number) => number;
export const derive_passphrase_key: (a: number, b: number, c: number, d: number) => [number, number];
export const get_tag_size: () => number;
export const otp_encrypt: (a: number, b: number, c: number, d: number) => [number, number, number, number];
export const __wbindgen_export_0: WebAssembly.Table;
export const __wbindgen_malloc: (a: number, b: number) => number;
export const __externref_table_dealloc: (a: number) => void;
export const __wbindgen_free: (a: number, b: number, c: number) => void;
export const __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
export const __wbindgen_start: () => void;
