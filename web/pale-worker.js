importScripts('pale.js');

let ctx = null;
let width = 0;
let height = 0;
let running = false;
let totalIterations = 0;

function getErrorMessage() {
  const len = Module._pale_get_error_len();
  const ptr = Module._pale_get_error_ptr();
  const msg = new TextDecoder().decode(Module.HEAPU8.subarray(ptr, ptr + len));
  Module._pale_clear_error();
  return msg;
}

Module.onRuntimeInitialized = () => {
  postMessage({ type: 'ready' });
};

onmessage = (e) => {
  const { type, data } = e.data;

  switch (type) {
    case 'create': {
      const { pixels, w, h, capacity, seed } = data;
      width = w;
      height = h;
      totalIterations = 0;

      const ptr = Module._malloc(pixels.length);
      Module.HEAPU8.set(pixels, ptr);
      ctx = Module._pale_create(ptr, w, h, capacity, BigInt(seed));
      Module._free(ptr);

      if (ctx === 0) {
        postMessage({ type: 'error', message: getErrorMessage() });
      } else {
        postMessage({ type: 'created' });
      }
      break;
    }

    case 'start':
      running = true;
      runLoop();
      break;

    case 'stop':
      running = false;
      break;

    case 'destroy':
      running = false;
      if (ctx) {
        Module._pale_destroy(ctx);
        ctx = null;
      }
      postMessage({ type: 'destroyed' });
      break;
  }
};

function runLoop() {
  if (!running || !ctx) return;

  const batchSize = 1000;
  const fitness = Module._pale_run_steps(ctx, batchSize);

  if (fitness === 0) {
    postMessage({ type: 'error', message: getErrorMessage() });
    running = false;
    return;
  }

  totalIterations += batchSize;

  const ptr = Module._pale_get_best_image(ctx);
  const len = width * height * 4;
  const pixels = new Uint8Array(Module.HEAPU8.buffer, ptr, len).slice();

  postMessage(
    { type: 'frame', pixels, fitness, iterations: totalIterations },
    [pixels.buffer]
  );

  setTimeout(runLoop, 0);
}
