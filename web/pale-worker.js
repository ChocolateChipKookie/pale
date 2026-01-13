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

// Classes
class WasmModule {
  /** @type {PaleExports} */
  exports;
  /** @type {ArrayBuffer | undefined} */
  #cachedMemoryBuffer;
  /** @type {Uint8Array | undefined} */
  #heapUint8Array;

  /** @param {WebAssembly.WebAssemblyInstantiatedSource} wasm */
  constructor(wasm) {
    this.exports = /** @type {PaleExports} */ (wasm.instance.exports);
  }

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

class Context {
  ptr;
  width;
  height;
  fps;
  running = false;

  /**
   * @param {number} ptr
   * @param {number} width
   * @param {number} height
   * @param {number} fps
   */
  constructor(ptr, width, height, fps) {
    this.ptr = ptr;
    this.width = width;
    this.height = height;
    this.fps = fps;
  }
}

// State
/** @type {WasmModule | null} */
let WASM = null;
/** @type {Context | null} */
let paleCtx = null;

// Functions
/** @param {string} location */
async function createWasmModule(location) {
  const decoder = new TextDecoder();
  const module = await WebAssembly.instantiateStreaming(fetch(location), {
    env: {
      /** @param {number} level @param {number} ptr @param {number} len */
      jsLog: (level, ptr, len) => {
        if (WASM === null) {
          console.error("jsLog called but WASM is null");
          return;
        }
        const methods = [console.error, console.warn, console.info, console.debug];
        const msg = decoder.decode(WASM.HEAP8.subarray(ptr, ptr + len));
        (methods[level] ?? console.log)(msg);
      },
    },
  });
  return new WasmModule(module);
}

function runLoop() {
  if (paleCtx === null || WASM === null || !paleCtx.running) return;

  const fitness = WASM.exports.pale_run_steps(paleCtx.ptr, 1000);
  if (fitness === 0n) {
    postMessage({ type: "error", message: "pale_run_steps failed" });
    return;
  }

  const pixelsPtr = WASM.exports.pale_get_best_image(paleCtx.ptr);
  if (pixelsPtr === 0) {
    postMessage({ type: "error", message: "pale_get_best_image failed" });
    return;
  }

  const len = paleCtx.width * paleCtx.height * 4;
  const pixels = new Uint8Array(WASM.HEAP8.buffer, pixelsPtr, len).slice();
  const iterations = WASM.exports.pale_get_iterations(paleCtx.ptr);
  if (iterations === 0) {
    postMessage({ type: "error", message: "pale_get_iterations failed" });
    return;
  }

  postMessage({ type: "frame", pixels, fitness, iterations }, [pixels.buffer]);
  setTimeout(runLoop, 0);
}

// Message handler
onmessage = async (e) => {
  const { type, data } = e.data;

  switch (type) {
    case "initialize":
      WASM = await createWasmModule("pale.wasm");
      postMessage({ type: "ready" });
      break;

    case "create": {
      if (WASM === null) {
        postMessage({ type: "error", message: "WASM not initialized" });
        break;
      }
      const ctxPtr = WASM.exports.pale_create(
        data.width,
        data.height,
        data.capacity,
        BigInt(data.seed),
      );
      if (ctxPtr === 0) {
        postMessage({ type: "error", message: "pale_create failed" });
        break;
      }

      paleCtx = new Context(ctxPtr, data.width, data.height, data.fps);

      const targetStart = WASM.exports.pale_get_target_image(ctxPtr);
      if (targetStart === 0) {
        postMessage({ type: "error", message: "pale_get_target_image failed" });
        break;
      }
      WASM.HEAP8.set(data.pixels, targetStart);

      const initialError = WASM.exports.pale_evaluate_best_solution(ctxPtr);
      if (initialError === 0n) {
        postMessage({ type: "error", message: "pale_evaluate_best_solution failed" });
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
          postMessage({ type: "error", message: "pale_destroy failed" });
          return;
        }
        paleCtx = null;
      }
      postMessage({ type: "destroyed" });
      break;
  }
};
