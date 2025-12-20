const canvas = document.getElementById("canvas");
const ctx = canvas.getContext("2d");
const startBtn = document.getElementById("startBtn");
const stopBtn = document.getElementById("stopBtn");
const resetBtn = document.getElementById("resetBtn");
const downloadBtn = document.getElementById("downloadBtn");
const imageInput = document.getElementById("imageInput");
const iterationsEl = document.getElementById("iterations");
const fitnessEl = document.getElementById("fitness");
const statusEl = document.getElementById("status");
const themeBtn = document.getElementById("themeBtn");
const targetFPS = 30;

// Theme handling
function getSystemTheme() {
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

function applyTheme(theme) {
  document.body.dataset.theme = theme === "light" ? "light" : "";
  themeBtn.textContent = theme === "light" ? "🌙" : "☀️";
}

const savedTheme = localStorage.getItem("theme");
applyTheme(savedTheme || getSystemTheme());

themeBtn.onclick = () => {
  const isLight = document.body.dataset.theme === "light";
  const newTheme = isLight ? "dark" : "light";
  applyTheme(newTheme);
  localStorage.setItem("theme", newTheme);
};

let worker = null;
let width = 512;
let height = 512;
let latestFrame = null;
let sourceImageData = null;
let isRunning = false;
let hasContext = false;

function log(msg) {
  console.log(`[Pale] ${msg}`);
}

function setStatus(s) {
  statusEl.textContent = s;
}

function updateButtons() {
  startBtn.disabled = !hasContext || isRunning;
  stopBtn.disabled = !isRunning;
  resetBtn.disabled = isRunning || !sourceImageData;
  imageInput.disabled = isRunning;
  downloadBtn.disabled = !sourceImageData;
}

function drawTestPattern() {
  const imageData = ctx.createImageData(width, height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      imageData.data[i] = x / 2;
      imageData.data[i + 1] = y / 2;
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
  setStatus("Paused");
  updateButtons();
  startBtn.textContent = "Continue";
  worker.postMessage({ type: "stop" });
  log("Paused");
};

resetBtn.onclick = () => {
  iterationsEl.textContent = "0";
  fitnessEl.textContent = "-";
  startBtn.textContent = "Start";

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

    const maxDim = 720;
    const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
    width = Math.round(img.width * scale);
    height = Math.round(img.height * scale);

    canvas.width = width;
    canvas.height = height;

    ctx.drawImage(img, 0, 0, width, height);
    sourceImageData = ctx.getImageData(0, 0, width, height);

    iterationsEl.textContent = "0";
    fitnessEl.textContent = "-";
    startBtn.textContent = "Start";

    log(`Loaded image: ${width}x${height}`);
    createContext();
  };
  img.src = URL.createObjectURL(file);
};

downloadBtn.onclick = () => {
  canvas.toBlob((blob) => {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `pale-${Date.now()}.png`;
    a.click();
    URL.revokeObjectURL(url);
  });
};

log("Initializing...");
initWorker();
drawTestPattern();
requestAnimationFrame(render);
