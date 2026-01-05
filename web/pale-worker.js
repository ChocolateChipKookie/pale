let wasm = null;
let exports = null;
let heap8 = null;

let ctx = null;
let width = 0;
let height = 0;
let running = false;

function handleErrorMessage() {
  const len = exports.pale_get_error_len();
  const ptr = exports.pale_get_error_ptr();
  const message = new TextDecoder().decode(heap8.subarray(ptr, ptr + len));
  exports.pale_clear_error();
  postMessage({ type: "error", message });
  running = false;
}

onmessage = async (e) => {
  const { type, data } = e.data;

  switch (type) {
    case "initialize": {
      wasm = await WebAssembly.instantiateStreaming(fetch("pale.wasm"), {
        env: {},
      });
      exports = wasm.instance.exports;
      heap8 = new Uint8Array(exports.memory.buffer);
      postMessage({ type: "ready" });
      break;
    }

    case "create": {
      const {
        imagePixels,
        imageWidth,
        imageHeight,
        targetFPS,
        capacity,
        seed,
      } = data;
      width = imageWidth;
      height = imageHeight;

      ctx = exports.pale_create(
        width,
        height,
        capacity,
        targetFPS,
        BigInt(seed),
      );

      if (ctx === 0) {
        handleErrorMessage();
        break;
      }

      const targetStart = exports.pale_get_target_image(ctx);
      if (targetStart === 0) {
        handleErrorMessage();
        break;
      }
      heap8.set(imagePixels, targetStart);

      const initialError = exports.pale_evaluate_best_solution(ctx);
      if (initialError === 0n) {
        handleErrorMessage();
        break;
      }

      postMessage({ type: "created" });
      break;
    }

    case "start":
      running = true;
      runLoop();
      break;

    case "stop":
      running = false;
      break;

    case "destroy":
      running = false;
      if (ctx) {
        const destroyRes = exports.pale_destroy(ctx);
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
  if (!running || !ctx) return;

  const fitness = exports.pale_run_step(ctx);
  if (fitness === 0n) {
    handleErrorMessage();
    return;
  }

  const ptr = exports.pale_get_best_image(ctx);
  if (ptr === 0) {
    handleErrorMessage();
    return;
  }

  const len = width * height * 4;
  const pixels = new Uint8Array(heap8.buffer, ptr, len).slice();
  const iterations = exports.pale_get_iterations(ctx);
  if (iterations === 0) {
    handleErrorMessage();
    return;
  }

  postMessage({ type: "frame", pixels, fitness, iterations }, [pixels.buffer]);

  setTimeout(runLoop, 0);
}
