importScripts("pale.js");

let ctx = null;
let width = 0;
let height = 0;
let running = false;

function handleErrorMessage() {
  const len = Module._pale_get_error_len();
  const ptr = Module._pale_get_error_ptr();
  const message = new TextDecoder().decode(
    Module.HEAPU8.subarray(ptr, ptr + len),
  );
  Module._pale_clear_error();
  postMessage({ type: "error", message });
  running = false;
}

Module.onRuntimeInitialized = () => {
  postMessage({ type: "ready" });
};

onmessage = (e) => {
  const { type, data } = e.data;

  switch (type) {
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

      const ptr = Module._malloc(imagePixels.length);
      Module.HEAPU8.set(imagePixels, ptr);
      ctx = Module._pale_create(
        ptr,
        width,
        height,
        capacity,
        targetFPS,
        BigInt(seed),
      );
      Module._free(ptr);

      if (ctx === 0) {
        handleErrorMessage();
      } else {
        postMessage({ type: "created" });
      }
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
        const destroyRes = Module._pale_destroy(ctx);
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

  const fitness = Module._pale_run_step(ctx);
  if (fitness === 0) {
    handleErrorMessage();
    return;
  }

  const ptr = Module._pale_get_best_image(ctx);
  if (ptr === 0) {
    handleErrorMessage();
    return;
  }

  const len = width * height * 4;
  const pixels = new Uint8Array(Module.HEAPU8.buffer, ptr, len).slice();
  const iterations = Module._pale_get_iterations(ctx);
  if (iterations === 0) {
    handleErrorMessage();
    return;
  }

  postMessage({ type: "frame", pixels, fitness, iterations }, [pixels.buffer]);

  setTimeout(runLoop, 0);
}
