/**
 * @typedef {Object} PaleExports
 * @property {WebAssembly.Memory} memory
 * @property {(width: number, height: number, capacity: number, seed: bigint) => number} pale_create
 * @property {(ctx: number) => number} pale_destroy
 * @property {(ctx: number) => number} pale_get_target_image
 * @property {(ctx: number) => bigint} pale_evaluate_best_solution
 * @property {(ctx: number, steps: number) => bigint} pale_run_steps
 * @property {(ctx: number) => number} pale_get_best_image
 * @property {(ctx: number) => number} pale_get_iterations
 */

class WasmModule {
  /** @type {PaleExports} */
  exports;

  /** @param wasm {WebAssembly.WebAssemblyInstantiatedSource} */
  constructor(wasm) {
    this.exports = /** @type {PaleExports} */ (wasm.instance.exports);
  }

  /** @type {ArrayBuffer | undefined} */
  #cachedMemoryBuffer;
  /** @type {Uint8Array | undefined} */
  #heapUint8Array;

  /** @returns {Uint8Array} */
  get HEAP8() {
    if (this.exports.memory.buffer !== this.#cachedMemoryBuffer) {
      this.#cachedMemoryBuffer = this.exports.memory.buffer;
      this.#heapUint8Array = new Uint8Array(this.exports.memory.buffer);
    }
    // @ts-expect-error heapUint8Array is guaranteed to be set after the above check
    return this.#heapUint8Array;
  }
}

/**
 * @param location {string}
 * @returns {Promise<WasmModule>}
 */
async function CreateWasmModule(location) {
  const decoder = new TextDecoder();
  const module = await WebAssembly.instantiateStreaming(fetch(location), {
    env: {
      /** @param {number} level @param {number} ptr @param {number} len */
      jsLog: (level, ptr, len) => {
        if (WASM === null) {
          console.error("jsLog called but WASM is null");
          return;
        }
        const methods = [
          console.error,
          console.warn,
          console.info,
          console.debug,
        ];
        const msg = decoder.decode(WASM.HEAP8.subarray(ptr, ptr + len));
        (methods[level] ?? console.log)(msg);
      },
    },
  });
  return new WasmModule(module);
}

/** @type {?WasmModule} */
let WASM = null;

class Context {
  /** @type {number} */
  ptr;
  /** @type {number} */
  width;
  /** @type {number} */
  height;
  /** @type {number} */
  fps;
  /** @type {boolean} */
  running;

  /**
   * @param ctxPtr {number}
   * @param width {number}
   * @param height {number}
   * @param fps {number}
   */
  constructor(ctxPtr, width, height, fps) {
    this.ptr = ctxPtr;
    this.width = width;
    this.height = height;
    this.fps = fps;
    this.running = false;
  }
}

/** @type {?Context} */
let paleCtx = null;

onmessage = async (e) => {
  const { type, data } = e.data;

  switch (type) {
    case "initialize": {
      WASM = await CreateWasmModule("pale.wasm");
      postMessage({ type: "ready" });
      break;
    }

    case "create": {
      if (WASM === null) {
        console.error("create called but WASM is null");
        break;
      }
      const ctxPtr = WASM.exports.pale_create(
        data.width,
        data.height,
        data.capacity,
        BigInt(data.seed),
      );

      if (ctxPtr === 0) {
        break;
      }

      paleCtx = new Context(ctxPtr, data.width, data.height, data.fps);

      const targetStart = WASM.exports.pale_get_target_image(ctxPtr);
      if (targetStart === 0) {
        break;
      }
      WASM.HEAP8.set(data.pixels, targetStart);

      const initialError = WASM.exports.pale_evaluate_best_solution(ctxPtr);
      if (initialError === 0n) {
        break;
      }

      postMessage({ type: "created" });
      break;
    }

    case "start":
      if (paleCtx === null) break;
      paleCtx.running = true;
      runLoop();
      break;

    case "stop":
      if (paleCtx === null) break;
      paleCtx.running = false;
      break;

    case "destroy":
      if (paleCtx === null) break;
      paleCtx.running = false;
      if (WASM !== null) {
        const destroyRes = WASM.exports.pale_destroy(paleCtx.ptr);
        if (destroyRes === 0) {
          return;
        }
        paleCtx = null;
      }
      postMessage({ type: "destroyed" });
      break;
  }
};

function runLoop() {
  if (paleCtx === null || WASM === null || !paleCtx.running) return;

  const fitness = WASM.exports.pale_run_steps(paleCtx.ptr, 1000);
  if (fitness === 0n) {
    return;
  }

  const pixelsPtr = WASM.exports.pale_get_best_image(paleCtx.ptr);
  if (pixelsPtr === 0) {
    return;
  }

  const len = paleCtx.width * paleCtx.height * 4;
  const pixels = new Uint8Array(WASM.HEAP8.buffer, pixelsPtr, len).slice();
  const iterations = WASM.exports.pale_get_iterations(paleCtx.ptr);
  if (iterations === 0) {
    return;
  }

  postMessage({ type: "frame", pixels, fitness, iterations }, [pixels.buffer]);

  setTimeout(runLoop, 0);
}
