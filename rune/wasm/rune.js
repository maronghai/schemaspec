// Rune WASM JavaScript Wrapper
// Loads rune.wasm and exposes the full compiler API for browsers and Deno.
//
// Build (produces zig-out/bin/rune.wasm):
//   cd rune && zig build -Dtarget=wasm32-wasi
//
// Usage (Browser):
//   import { compile, lint, version } from './rune.js';
//   const sql = await compile('$ d\n\n# t\nid n++', { dialect: 'pg' });
//
// Usage (Deno):
//   import { compile, version } from './rune.js';
//   console.log(await compile('...', { dialect: 'mysql' }));

let instance = null;
let loadPromise = null;

// Minimal WASI stub. The wasm module links libc so it imports
// wasi_snapshot_preview1, but the compile/lint/docs pipelines only touch
// entropy (random_get) and clocks; every other stub returns ENOSYS (52).
function makeWasi(memLike) {
  const mem = memLike;
  return new Proxy({}, {
    get(_, name) {
      if (name === 'random_get') {
        return (ptr, len) => {
          crypto.getRandomValues(new Uint8Array(mem.buffer, Number(ptr), Number(len)));
          return 0;
        };
      }
      if (name === 'clock_time_get' || name === 'clock_res_get') {
        return (_id, _precision, out) => {
          new DataView(mem.buffer).setBigUint64(Number(out), BigInt(Date.now()) * 1000000n, true);
          return 0;
        };
      }
      if (name === 'environ_sizes_get') {
        return (countOut, bufSizeOut) => {
          const dv = new DataView(mem.buffer);
          dv.setUint32(Number(countOut), 0, true);
          dv.setUint32(Number(bufSizeOut), 0, true);
          return 0;
        };
      }
      return () => 52; // ENOSYS — not reached by compiler pipelines
    },
  });
}

async function loadWasm(wasmPath) {
  if (instance) return instance;
  if (loadPromise) return loadPromise;
  loadPromise = (async () => {
    let bytes;
    if (typeof Deno !== 'undefined') {
      bytes = await Deno.readFile(wasmPath || 'zig-out/bin/rune.wasm');
    } else {
      const resp = await fetch(wasmPath || 'rune.wasm');
      if (!resp.ok) throw new Error(`Failed to load rune.wasm: ${resp.status}`);
      bytes = await resp.arrayBuffer();
    }
    const mod = await WebAssembly.compile(bytes);
    // The stubs only touch `memory` when actually called (after the real
    // instance exists), so a lazily-resolved holder works for both passes.
    let memRef = null;
    const wasi = makeWasi({ get buffer() { return memRef.buffer; } });
    const inst = await WebAssembly.instantiate(mod, { wasi_snapshot_preview1: wasi });
    memRef = inst.exports.memory;
    instance = inst;
    return inst;
  })();
  return loadPromise;
}

function readCStr(mem, ptr) {
  const view = new Uint8Array(mem.buffer);
  let end = ptr;
  while (view[end] !== 0) end++;
  return new TextDecoder().decode(view.slice(ptr, end));
}

/** Call one rune_*(in_ptr, in_len, opts_ptr, opts_len) export with strings. */
async function call1(fnName, input, options = {}) {
  const inst = await loadWasm(options.wasmPath);
  const ex = inst.exports;
  const mem = ex.memory;

  const inBytes = new TextEncoder().encode(input ?? '');
  const optBytes = new TextEncoder().encode(options.options ?? '');

  const inPtr = Number(ex.rune_wasm_alloc(inBytes.length));
  new Uint8Array(mem.buffer, inPtr, inBytes.length).set(inBytes);
  const optPtr = Number(ex.rune_wasm_alloc(optBytes.length));
  new Uint8Array(mem.buffer, optPtr, optBytes.length).set(optBytes);

  const result = ex[fnName](inPtr, inBytes.length, optPtr, optBytes.length);
  if (result === null || result === undefined || Number(result) === 0) {
    const errPtr = ex.rune_last_error();
    const code = ex.rune_last_error_code();
    const msg = errPtr ? readCStr(mem, Number(errPtr)) : `${fnName} failed`;
    throw Object.assign(new Error(msg), { code });
  }
  return readCStr(mem, Number(result));
}

/** Call a two-input export (diff/migrate). */
async function call2(fnName, oldText, newText, options = {}) {
  const inst = await loadWasm(options.wasmPath);
  const ex = inst.exports;
  const mem = ex.memory;

  const oldBytes = new TextEncoder().encode(oldText ?? '');
  const newBytes = new TextEncoder().encode(newText ?? '');
  const optBytes = new TextEncoder().encode(options.options ?? '');

  const oldPtr = Number(ex.rune_wasm_alloc(oldBytes.length));
  new Uint8Array(mem.buffer, oldPtr, oldBytes.length).set(oldBytes);
  const newPtr = Number(ex.rune_wasm_alloc(newBytes.length));
  new Uint8Array(mem.buffer, newPtr, newBytes.length).set(newBytes);
  const optPtr = Number(ex.rune_wasm_alloc(optBytes.length));
  new Uint8Array(mem.buffer, optPtr, optBytes.length).set(optBytes);

  const result = ex[fnName](oldPtr, oldBytes.length, newPtr, newBytes.length, optPtr, optBytes.length);
  if (result === null || result === undefined || Number(result) === 0) {
    const errPtr = ex.rune_last_error();
    const msg = errPtr ? readCStr(mem, Number(errPtr)) : `${fnName} failed`;
    throw Object.assign(new Error(msg), { code: ex.rune_last_error_code() });
  }
  return readCStr(mem, Number(result));
}

export const dialects = ['mysql', 'pg', 'sqlite', 'mssql', 'oracle', 'db2'];

/**
 * Compile a Rune schema to SQL DDL.
 * @param {string} schema - The .ss schema text
 * @param {{dialect?: string, options?: string, wasmPath?: string}} [options]
 * @returns {Promise<string>} Generated SQL
 */
export async function compile(schema, options = {}) {
  return call1('rune_compile', schema, { options: options.dialect ? `dialect=${options.dialect}` : '', ...options });
}

/** Validate a schema; throws on invalid, returns report text on success. */
export async function validate(schema, options = {}) {
  return call1('rune_validate', schema, options);
}

/** Print schema statistics. */
export async function stats(schema, options = {}) {
  return call1('rune_stats', schema, options);
}

/** Diff two schemas; returns human-readable diff text. */
export async function diff(oldSchema, newSchema, options = {}) {
  return call2('rune_diff', oldSchema, newSchema, options);
}

/** Generate ALTER TABLE migration SQL from old → new schema. */
export async function migrate(oldSchema, newSchema, options = {}) {
  return call2('rune_migrate', oldSchema, newSchema, options);
}

/** Lint a schema for quality issues. */
export async function lint(schema, options = {}) {
  return call1('rune_lint', schema, options);
}

/** Auto-format a .ss source string. */
export async function format(schema, options = {}) {
  return call1('rune_format', schema, options);
}

/** Extract common fields into templates (`rune tune`). */
export async function tune(schema, options = {}) {
  return call1('rune_tune', schema, options);
}

/** Generate ORM/API-schema output; generator name required. */
export async function generate(schema, generator, options = {}) {
  return call1('rune_generate', schema, { options: `generator=${generator}`, ...options });
}

/** Export schema structure as JSON. */
export async function exportJson(schema, options = {}) {
  return call1('rune_export', schema, options);
}

/** Generate Markdown documentation. */
export async function docs(schema, options = {}) {
  return call1('rune_docs', schema, options);
}

/** Reverse-engineer SQL DDL back to .ss source. */
export async function reverse(sql, options = {}) {
  return call1('rune_reverse', sql, options);
}

/** Get the embedded Rune version. */
export async function version(options = {}) {
  const inst = await loadWasm(options.wasmPath);
  return readCStr(inst.exports.memory, Number(inst.exports.rune_version()));
}

/** Reset the WASM arena allocator (frees memory between long sessions). */
export async function reset(options = {}) {
  const inst = await loadWasm(options.wasmPath);
  inst.exports.rune_reset();
}
