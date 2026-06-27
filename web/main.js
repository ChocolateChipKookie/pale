// DOM elements
const canvas = /** @type {HTMLCanvasElement} */ (
  document.getElementById("canvas")
);
const ctx = /** @type {CanvasRenderingContext2D} */ (canvas.getContext("2d"));

const startBtn = /** @type {HTMLButtonElement} */ (
  document.getElementById("startBtn")
);
const stopBtn = /** @type {HTMLButtonElement} */ (
  document.getElementById("stopBtn")
);
const resetBtn = /** @type {HTMLButtonElement} */ (
  document.getElementById("resetBtn")
);
const downloadBtn = /** @type {HTMLButtonElement} */ (
  document.getElementById("downloadBtn")
);
const imageInput = /** @type {HTMLInputElement} */ (
  document.getElementById("imageInput")
);
const alphaInput = /** @type {HTMLInputElement} */ (
  document.getElementById("alphaInput")
);

const presetBtn = /** @type {HTMLButtonElement} */ (
  document.getElementById("presetBtn")
);
const thumbGrid = /** @type {HTMLElement} */ (
  document.getElementById("thumbGrid")
);

const iterationsEl = /** @type {HTMLElement} */ (
  document.getElementById("iterations")
);
const rectanglesEl = /** @type {HTMLElement} */ (
  document.getElementById("rectangles")
);
const errorEl = /** @type {HTMLElement} */ (document.getElementById("error"));
const statusEl = /** @type {HTMLElement} */ (document.getElementById("status"));
const themeBtn = /** @type {HTMLButtonElement} */ (
  document.getElementById("themeBtn")
);

// State
const worker = new Worker("pale-worker.js");
let width = 512;
let height = 512;
/** @type {Uint8Array | null} */
let latestFrame = null;
/** @type {ImageData | null} */
let sourceImageData = null;
let isRunning = false;
let hasContext = false;

// UI helpers
/** @param {string} s */
function setStatus(s) {
  statusEl.textContent = s;
}

function resetUI() {
  iterationsEl.textContent = "0";
  rectanglesEl.textContent = "0";
  errorEl.textContent = "-";
  startBtn.textContent = "Start";
}

/**
 * @param {HTMLElement} el
 * @param {boolean} disabled
 * @param {string} hint
 */
function setDisabled(el, disabled, hint) {
  if ("disabled" in el) {
    /** @type {HTMLButtonElement | HTMLInputElement} */ (el).disabled =
      disabled;
  }
  if (disabled) el.title = hint;
  else el.removeAttribute("title");
}

function updateButtons() {
  setDisabled(
    startBtn,
    !sourceImageData || isRunning,
    !sourceImageData ? "Load an image first" : "Already running",
  );
  setDisabled(stopBtn, !isRunning, "Not running");
  setDisabled(
    resetBtn,
    isRunning || !hasContext,
    isRunning ? "Stop first" : "No active session — press Start",
  );
  setDisabled(imageInput, isRunning, "Stop first");
  setDisabled(presetBtn, isRunning, "Stop first");
  setDisabled(alphaInput, hasContext, "Press Reset to change");
  setDisabled(downloadBtn, !sourceImageData, "Load an image first");
}

// Rendering
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

function render() {
  if (!latestFrame) return;
  const imageData = new ImageData(
    new Uint8ClampedArray(latestFrame),
    width,
    height,
  );
  ctx.putImageData(imageData, 0, 0);
  latestFrame = null;
}

// Worker communication
function createContext() {
  if (!sourceImageData) return;
  worker.postMessage({
    type: "create",
    data: {
      pixels: sourceImageData.data,
      width,
      height,
      fps: 30,
      capacity: 10000,
      seed: Date.now(),
      enableAlpha: alphaInput.checked,
    },
  });
}

worker.onmessage = (/** @type {MessageEvent} */ e) => {
  const { type, pixels, fitness, iterations, rectangles, message } = e.data;
  switch (type) {
    case "ready":
      setStatus("Ready");
      updateButtons();
      break;
    case "created":
      hasContext = true;
      isRunning = true;
      setStatus("Running");
      updateButtons();
      worker.postMessage({ type: "start" });
      break;
    case "frame":
      latestFrame = pixels;
      iterationsEl.textContent = iterations.toLocaleString();
      rectanglesEl.textContent = rectangles.toLocaleString();
      errorEl.textContent = fitness.toLocaleString();
      requestAnimationFrame(render);
      break;
    case "destroyed":
      hasContext = false;
      updateButtons();
      break;
    case "error":
      console.error(`WASM error: ${message}`);
      setStatus("WASM error");
      isRunning = false;
      updateButtons();
      break;
  }
};

worker.onerror = (/** @type {ErrorEvent} */ e) => {
  console.error(`Worker error: ${e.message}`);
  setStatus("Worker error");
};

// Event handlers
startBtn.onclick = () => {
  if (!sourceImageData) return;
  if (!hasContext) {
    createContext();
    return;
  }
  isRunning = true;
  setStatus("Running");
  updateButtons();
  worker.postMessage({ type: "start" });
};

stopBtn.onclick = () => {
  isRunning = false;
  setStatus("Paused");
  updateButtons();
  startBtn.textContent = "Continue";
  worker.postMessage({ type: "stop" });
};

resetBtn.onclick = () => {
  resetUI();
  if (sourceImageData) {
    ctx.putImageData(sourceImageData, 0, 0);
  }
  if (hasContext) {
    worker.postMessage({ type: "destroy" });
  }
  setStatus("Reset");
};

/** @param {HTMLImageElement} img */
function applyImage(img) {
  if (hasContext) {
    worker.postMessage({ type: "destroy" });
    hasContext = false;
  }

  const maxDim = 480;
  const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
  width = Math.round(img.width * scale);
  height = Math.round(img.height * scale);

  canvas.width = width;
  canvas.height = height;

  ctx.drawImage(img, 0, 0, width, height);
  sourceImageData = ctx.getImageData(0, 0, width, height);
  resetUI();
  updateButtons();
  setStatus("Ready to start");
}

/** @param {File} file */
function loadImageFile(file) {
  if (!file.type.startsWith("image/")) return;
  const img = new Image();
  img.onload = () => applyImage(img);
  img.src = URL.createObjectURL(file);
}

/** @param {string} url */
function loadImageFromUrl(url) {
  const img = new Image();
  img.onload = () => applyImage(img);
  img.src = url;
}

imageInput.onchange = () => {
  const file = imageInput.files?.[0];
  if (file) loadImageFile(file);
};

canvas.ondragover = (/** @type {DragEvent} */ e) => {
  if (isRunning) return;
  e.preventDefault();
  canvas.classList.add("dragover");
};

canvas.ondragleave = () => {
  canvas.classList.remove("dragover");
};

canvas.ondrop = (/** @type {DragEvent} */ e) => {
  e.preventDefault();
  canvas.classList.remove("dragover");
  if (isRunning) return;
  const file = e.dataTransfer?.files?.[0];
  if (file) loadImageFile(file);
};

// Examples: fetch the manifest on click and populate the grid, then replace
// the button with the grid. Nothing is requested until the button is pressed.
async function loadPresets() {
  try {
    const res = await fetch("images.json");
    /** @type {string[]} */
    const names = await res.json();
    for (const name of names) {
      const img = new Image();
      img.src = `${name}.thumb.png`;
      img.alt = name;
      img.onclick = () => {
        if (isRunning) return;
        loadImageFromUrl(`${name}.png`);
      };
      thumbGrid.appendChild(img);
    }
    presetBtn.hidden = true;
    thumbGrid.hidden = false;
  } catch (e) {
    console.error(`Failed to load image manifest: ${e}`);
  }
}

presetBtn.onclick = loadPresets;

downloadBtn.onclick = () => {
  canvas.toBlob((blob) => {
    if (blob === null) return;
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `pale-${Date.now()}.png`;
    a.click();
    URL.revokeObjectURL(url);
  });
};

// Theme
function getSystemTheme() {
  return window.matchMedia("(prefers-color-scheme: light)").matches
    ? "light"
    : "dark";
}

/** @param {string} theme */
function applyTheme(theme) {
  document.body.dataset.theme = theme === "light" ? "light" : "";
  themeBtn.textContent = theme === "light" ? "🌙" : "☀️";
}

themeBtn.onclick = () => {
  const isLight = document.body.dataset.theme === "light";
  const newTheme = isLight ? "dark" : "light";
  applyTheme(newTheme);
  localStorage.setItem("theme", newTheme);
};

// Init
applyTheme(localStorage.getItem("theme") || getSystemTheme());
drawTestPattern();
worker.postMessage({ type: "initialize" });
