class WasmModule {
  exports;

  /** @param wasm {WebAssembly.WebAssemblyInstantiatedSource} */
  constructor(wasm) {
    this.exports = wasm.instance.exports;
  }

  #cachedMemoryBuffer;
  #heapUint8Array;

  /** @returns {Uint8Array} */
  get HEAP8() {
    if (this.exports.memory.buffer !== this.#cachedMemoryBuffer) {
      this.#heapUint8Array = new Uint8Array(this.exports.memory.buffer);
    }
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
      jsLog: (level, ptr, len) => {
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
let ctx = null;

onmessage = async (e) => {
  const { type, data } = e.data;

  switch (type) {
    case "initialize": {
      WASM = await CreateWasmModule("pale.wasm");
      postMessage({ type: "ready" });
      break;
    }

    case "create": {
      const ctxPtr = WASM.exports.pale_create(
        data.width,
        data.height,
        data.capacity,
        BigInt(data.seed),
      );

      if (ctxPtr === 0) {
        handleErrorMessage();
        break;
      }

      ctx = new Context(ctxPtr, data.width, data.height, data.fps);

      const targetStart = WASM.exports.pale_get_target_image(ctxPtr);
      if (targetStart === 0) {
        handleErrorMessage();
        break;
      }
      WASM.HEAP8.set(data.pixels, targetStart);

      const initialError = WASM.exports.pale_evaluate_best_solution(ctxPtr);
      if (initialError === 0n) {
        handleErrorMessage();
        break;
      }

      postMessage({ type: "created" });
      break;
    }

    case "start":
      ctx.running = true;
      runLoop();
      break;

    case "stop":
      ctx.running = false;
      break;

    case "destroy":
      ctx.running = false;
      if (ctx !== null) {
        const destroyRes = WASM.exports.pale_destroy(ctx.ptr);
        if (destroyRes === 0) {
          handleErrorMessage();
          return;
        }
        ctx = null;
      }
      postMessage({ type: "destroyed" });
      break;
  }
};

function runLoop() {
  if (ctx === null || !ctx.running) return;

  const fitness = WASM.exports.pale_run_steps(ctx.ptr, 1000);
  if (fitness === 0n) {
    handleErrorMessage();
    return;
  }

  const pixelsPtr = WASM.exports.pale_get_best_image(ctx.ptr);
  if (pixelsPtr === 0) {
    handleErrorMessage();
    return;
  }

  const len = ctx.width * ctx.height * 4;
  const pixels = new Uint8Array(WASM.HEAP8.buffer, pixelsPtr, len).slice();
  const iterations = WASM.exports.pale_get_iterations(ctx.ptr);
  if (iterations === 0) {
    handleErrorMessage();
    return;
  }

  postMessage({ type: "frame", pixels, fitness, iterations }, [pixels.buffer]);

  setTimeout(runLoop, 0);
}
