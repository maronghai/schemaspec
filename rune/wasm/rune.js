// Rune WASM JavaScript Wrapper
// Provides compile() and version() for browser and Deno environments.
//
// Usage (Deno):
//   deno run --allow-read rune.js compile schema.ss -d pg
//
// Usage (Browser):
//   import { compile, version } from './rune.js';
//   const sql = await compile('t { id n }', { dialect: 'pg' });
//
// Build:
//   cd rune && zig build -Dtarget=wasm32-wasi
//   The output is at zig-out/bin/rune.wasm

let instance = null;

async function loadWasm(path) {
    if (instance) return instance;
    const wasmBytes = await Deno.readFile(path || 'zig-out/bin/rune.wasm');
    const { instance: inst } = await WebAssembly.instantiate(wasmBytes);
    instance = inst;
    return instance;
}

function readString(ptr, len) {
    const memory = instance.exports.memory;
    const bytes = new Uint8Array(memory.buffer, ptr, len);
    return new TextDecoder().decode(bytes);
}

/**
 * Compile a Rune schema to SQL.
 * @param {string} schema - The .ss schema text
 * @param {object} [options] - { dialect: 'mysql'|'pg'|'sqlite'|'mssql'|'oracle'|'db2' }
 * @returns {Promise<string>} Generated SQL
 */
export async function compile(schema, options = {}) {
    const inst = await loadWasm(options.wasmPath);
    const exports = inst.exports;
    const memory = exports.memory;

    // Encode inputs as UTF-8
    const encoder = new TextEncoder();
    const schemaBytes = encoder.encode(schema);
    const optsStr = options.dialect ? `dialect=${options.dialect}` : '';
    const optsBytes = encoder.encode(optsStr);

    // Allocate memory in WASM for inputs
    const schemaPtr = exports.rune_alloc(schemaBytes.length);
    new Uint8Array(memory.buffer, schemaPtr, schemaBytes.length).set(schemaBytes);

    const optsPtr = exports.rune_alloc(optsBytes.length);
    new Uint8Array(memory.buffer, optsPtr, optsBytes.length).set(optsBytes);

    // Call compile
    const resultPtr = exports.rune_compile(schemaPtr, schemaBytes.length, optsPtr, optsBytes.length);

    if (resultPtr === 0) {
        exports.rune_free(schemaPtr, schemaBytes.length);
        exports.rune_free(optsPtr, optsBytes.length);
        throw new Error('Schema compilation failed');
    }

    // Read result (null-terminated string)
    const memoryView = new Uint8Array(memory.buffer);
    let end = resultPtr;
    while (memoryView[end] !== 0) end++;
    const sql = readString(resultPtr, end - resultPtr);

    // Free inputs
    exports.rune_free(schemaPtr, schemaBytes.length);
    exports.rune_free(optsPtr, optsBytes.length);

    return sql;
}

/**
 * Get the Rune version.
 * @returns {Promise<string>}
 */
export async function version() {
    const inst = await loadWasm();
    const ptr = inst.exports.rune_version();
    if (ptr === 0) return 'unknown';
    const memoryView = new Uint8Array(inst.exports.memory.buffer);
    let end = ptr;
    while (memoryView[end] !== 0) end++;
    return readString(ptr, end - ptr);
}

// ─── Deno CLI Entry Point ──────────────────────────────────────
if (typeof Deno !== 'undefined' && Deno.args.length > 0) {
    const args = Deno.args;
    if (args[0] === 'compile' && args.length >= 2) {
        const filePath = args[1];
        let dialect = 'mysql';
        for (let i = 2; i < args.length; i++) {
            if (args[i] === '-d' || args[i] === '--dialect') {
                dialect = args[i + 1] || 'mysql';
                i++;
            }
        }
        const schema = await Deno.readTextFile(filePath);
        const sql = await compile(schema, { dialect });
        console.log(sql);
    } else if (args[0] === 'version' || args[0] === '--version') {
        console.log('rune', await version());
    } else {
        console.error('Usage: deno run rune.js compile <file.ss> [-d dialect]');
        console.error('       deno run rune.js version');
        Deno.exit(1);
    }
}
