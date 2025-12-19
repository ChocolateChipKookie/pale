const canvas = document.getElementById("canvas");
const ctx = canvas.getContext("2d");
const startBtn = document.getElementById("startBtn");
const stopBtn = document.getElementById("stopBtn");
const resetBtn = document.getElementById("resetBtn");
const imageInput = document.getElementById("imageInput");
const iterationsEl = document.getElementById("iterations");
const fitnessEl = document.getElementById("fitness");
const statusEl = document.getElementById("status");
const logEl = document.getElementById("log");
const targetFPS = 30;

let worker = null;
let width = 256;
let height = 256;
let latestFrame = null;
let sourceImageData = null;
let isRunning = false;
let hasContext = false;

function log(msg) {
  const time = new Date().toISOString().substr(11, 12);
  logEl.textContent += `[${time}] ${msg}\n`;
  logEl.scrollTop = logEl.scrollHeight;
}

function setStatus(s) {
  statusEl.textContent = s;
}

function updateButtons() {
  startBtn.disabled = !hasContext || isRunning;
  stopBtn.disabled = !isRunning;
  resetBtn.disabled = !hasContext && !sourceImageData;
  imageInput.disabled = isRunning;
}

function drawTestPattern() {
  const imageData = ctx.createImageData(width, height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      imageData.data[i] = x;
      imageData.data[i + 1] = y;
      imageData.data[i + 2] = 128;
      imageData.data[i + 3] = 255;
    }
  }
  ctx.putImageData(imageData, 0, 0);
  sourceImageData = imageData;
}

function createContext() {
  if (!sourceImageData) {
    log("No image loaded");
    return;
  }

  worker.postMessage({
    type: "create",
    data: {
      imagePixels: sourceImageData.data,
      imageWidth: width,
      imageHeight: height,
      targetFPS: targetFPS,
      capacity: 1000,
      seed: Date.now(),
    },
  });
}

function initWorker() {
  worker = new Worker("pale-worker.js");

  worker.onmessage = (e) => {
    const { type, pixels, fitness, iterations, message } = e.data;

    switch (type) {
      case "ready":
        log("Worker ready");
        setStatus("Ready");
        drawTestPattern();
        createContext();
        break;

      case "created":
        log("Context created");
        hasContext = true;
        setStatus("Ready to start");
        updateButtons();
        break;

      case "frame":
        latestFrame = pixels;
        iterationsEl.textContent = iterations.toLocaleString();
        fitnessEl.textContent = fitness.toLocaleString();
        break;

      case "destroyed":
        log("Context destroyed");
        hasContext = false;
        updateButtons();
        break;

      case "error":
        log(`WASM error: ${message}`);
        setStatus("WASM error");
        isRunning = false;
        updateButtons();
        break;
    }
  };

  worker.onerror = (e) => {
    log(`Worker error: ${e.message}`);
    setStatus("Worker error");
  };
}

function render() {
  if (latestFrame) {
    const imageData = new ImageData(
      new Uint8ClampedArray(latestFrame),
      width,
      height,
    );
    ctx.putImageData(imageData, 0, 0);
    latestFrame = null;
  }
  requestAnimationFrame(render);
}

startBtn.onclick = () => {
  if (!hasContext) return;
  isRunning = true;
  setStatus("Running");
  updateButtons();
  worker.postMessage({ type: "start" });
  log("Started");
};

stopBtn.onclick = () => {
  isRunning = false;
  setStatus("Stopped");
  updateButtons();
  worker.postMessage({ type: "stop" });
  log("Stopped");
};

resetBtn.onclick = () => {
  isRunning = false;
  worker.postMessage({ type: "destroy" });

  iterationsEl.textContent = "0";
  fitnessEl.textContent = "-";

  if (sourceImageData) {
    ctx.putImageData(sourceImageData, 0, 0);
    createContext();
  }

  setStatus("Reset");
  log("Reset");
};

imageInput.onchange = (e) => {
  const file = e.target.files[0];
  if (!file) return;

  const img = new Image();
  img.onload = () => {
    if (hasContext) {
      worker.postMessage({ type: "destroy" });
      hasContext = false;
    }

    canvas.width = img.width;
    canvas.height = img.height;
    width = img.width;
    height = img.height;

    ctx.drawImage(img, 0, 0);
    sourceImageData = ctx.getImageData(0, 0, width, height);

    iterationsEl.textContent = "0";
    fitnessEl.textContent = "-";

    log(`Loaded image: ${width}x${height}`);
    createContext();
  };
  img.src = URL.createObjectURL(file);
};

log("Initializing...");
initWorker();
requestAnimationFrame(render);
