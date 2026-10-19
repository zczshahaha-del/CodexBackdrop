import fs from "node:fs";
import path from "node:path";

const argumentsList = process.argv.slice(2);
const action = argumentsList[0] || "status";
const portText = argumentsList[1] || "9224";
const assetPath = argumentsList[2];
const transparencyText = action === "set-transparency"
  ? argumentsList[2] || "0.70"
  : argumentsList[3] || "0.70";
const clarityModeText = action === "set-transparency"
  ? argumentsList[3] || "linked"
  : argumentsList[4] || "linked";
const port = Number(portText);
const maxVideoBytes = 200 * 1024 * 1024;
const maxImageBytes = 80 * 1024 * 1024;
const initialTransparency = Number.isFinite(Number(transparencyText)) ? Number(transparencyText) : 0.70;
const keepBackgroundClear = clarityModeText === "clear";

const sharedCSS = `
  #codex-live-background {
    position: fixed;
    inset: 0;
    z-index: 0;
    overflow: hidden;
    pointer-events: none;
    background: #030611;
  }
  #codex-live-background-video,
  #codex-live-background-image,
  #codex-live-background-canvas {
    position: absolute;
    inset: 0;
    z-index: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  #codex-live-effects-overlay {
    position: absolute;
    inset: 0;
    z-index: 1;
    width: 100%;
    height: 100%;
    pointer-events: none;
    opacity: .58;
    mix-blend-mode: screen;
  }
  #codex-live-background-video {
    filter: brightness(var(--codex-asset-brightness, 1)) saturate(var(--codex-asset-saturation, 1.08));
  }
  #codex-live-background-image {
    filter: brightness(var(--codex-asset-brightness, 1)) saturate(var(--codex-asset-saturation, 1.08));
  }
  #codex-live-background::after {
    content: "";
    position: absolute;
    inset: 0;
    z-index: 1;
    background: linear-gradient(180deg, rgba(2, 6, 20, .04), rgb(2 6 18 / var(--codex-shade-alpha, .28)));
  }
  html, body, #root { background: transparent !important; }
  #root { position: relative; z-index: 2; }
  #root main.flex.h-full,
  #root [class*="_PageSurfaceLayout_"],
  #root .messaging-root,
  #root .thread-pane,
  #root webview.bg-surface {
    background: transparent !important;
    backdrop-filter: none !important;
  }
  #root [class*="_MainContentSurface_"] {
    background: rgb(6 10 24 / var(--codex-main-alpha, .26)) !important;
    backdrop-filter: blur(var(--codex-main-blur, 5px)) saturate(112%) !important;
  }
  #root aside.app-shell-left-panel {
    background: rgb(5 9 23 / var(--codex-sidebar-alpha, .34)) !important;
    backdrop-filter: blur(var(--codex-sidebar-blur, 7px)) saturate(120%) !important;
  }
  #root aside.app-shell-left-panel::after {
    /* Codex extends this decoration into the chat; inherited tint covers text. */
    background: transparent !important;
  }
  #root [class*="_ComposerLayoutRoot_"]:not([data-composer-utility-bar-variant="home"]) {
    background: rgb(11 17 34 / var(--codex-composer-alpha, .70)) !important;
    backdrop-filter: blur(var(--codex-composer-blur, 7px)) saturate(112%) !important;
    border-color: rgba(255, 255, 255, .12) !important;
  }
  #root [class*="_ComposerLayoutRoot_"][data-composer-utility-bar-variant="home"] {
    /* Home paints its rounded surface on the inner body, not this layout box. */
    background: transparent !important;
    backdrop-filter: none !important;
    --composer-layout-surface-background: rgb(11 17 34 / var(--codex-composer-alpha, .70)) !important;
    --composer-layout-surface-backdrop-filter: blur(var(--codex-composer-blur, 7px)) saturate(112%) !important;
  }
  #root .pointer-events-none.absolute.inset-x-0.bottom-0[class*="bg-gradient-to-t"][class*="from-surface"] {
    background-image: none !important;
    background-color: transparent !important;
  }
  #root, #root * {
    --app-color-background-surface: rgb(7 12 27 / var(--codex-surface-alpha, .32));
    --app-color-background-surface-under: rgb(4 8 20 / var(--codex-under-alpha, .34));
    --app-color-text-foreground: rgba(248, 250, 255, .97);
    --app-color-text-foreground-secondary: rgba(224, 231, 245, .82);
    --app-color-text-foreground-tertiary: rgba(208, 218, 237, .66);
    --color-text: rgba(248, 250, 255, .97);
    --color-codex-description: rgba(220, 228, 243, .72);
    --color-surface: rgb(7 12 27 / var(--codex-surface-alpha, .32)) !important;
    --color-surface-secondary: rgb(4 8 20 / var(--codex-under-alpha, .34)) !important;
    --color-surface-canvas: rgb(4 8 20 / var(--codex-under-alpha, .34)) !important;
    --color-surface-card: rgb(7 12 27 / var(--codex-surface-alpha, .32)) !important;
    --color-token-main-surface-primary: rgb(7 12 27 / var(--codex-surface-alpha, .32)) !important;
    --color-token-side-bar-background: rgb(5 9 23 / var(--codex-sidebar-alpha, .34)) !important;
    --color-token-bg-primary: rgb(4 8 20 / var(--codex-under-alpha, .34)) !important;
    --color-token-bg-secondary: rgb(4 8 20 / var(--codex-under-alpha, .34)) !important;
    --color-token-bg-tertiary: rgb(4 8 20 / var(--codex-under-alpha, .34)) !important;
    --color-background-panel: rgb(7 12 27 / var(--codex-surface-alpha, .32)) !important;
  }
  #root [class*="_ComposerLayoutRoot_"] .ProseMirror [data-placeholder]::before {
    color: rgba(220, 228, 243, .58) !important;
  }
`;

// These layers are painted once; only transform/opacity animate, not gradients or blur.
const lightweightEffects = new Set(["gradient", "aurora", "bokeh", "meteors"]);
const lightweightCSS = `
  #codex-live-background .codex-light-stage {
    position: absolute; inset: 0; overflow: hidden;
  }
  #codex-live-background .codex-light-layer {
    position: absolute; pointer-events: none;
    will-change: transform, opacity;
    animation: codex-light-drift var(--duration, 20s) ease-in-out var(--delay, 0s) infinite alternate;
  }
  #codex-live-background[data-paused="true"] .codex-light-layer {
    animation-play-state: paused !important;
  }
  @keyframes codex-light-drift {
    from { transform: translate3d(-4%, -3%, 0) rotate(-8deg) scale(1); opacity: .65; }
    to { transform: translate3d(12%, 9%, 0) rotate(12deg) scale(1.12); opacity: .95; }
  }
  #codex-live-background .codex-light-gradient {
    background: linear-gradient(140deg, #172846, #29203b 55%, #12373e);
  }
  #codex-live-background .codex-gradient-blob {
    width: 85%; height: 100%; left: -15%; top: -25%;
    background: radial-gradient(ellipse, rgba(102, 84, 223, .85), rgba(89, 55, 144, .35) 40%, transparent 70%);
  }
  #codex-live-background .codex-gradient-blob:nth-child(2) {
    left: 42%; top: 0; --duration: 26s; --delay: -12s;
    background: radial-gradient(ellipse, rgba(28, 153, 169, .78), rgba(20, 105, 127, .35) 38%, transparent 70%);
  }
  #codex-live-background .codex-gradient-blob:nth-child(3) {
    left: 2%; top: 40%; --duration: 32s; --delay: -20s;
    background: radial-gradient(ellipse, rgba(177, 71, 126, .65), rgba(139, 59, 105, .28) 40%, transparent 70%);
  }
  #codex-live-background .codex-light-aurora {
    background: linear-gradient(170deg, #061326, #082b32 65%, #101a34);
  }
  #codex-live-background .codex-aurora-band {
    width: 130%; height: 65%; left: -20%; top: -16%; --duration: 24s;
    animation-name: codex-aurora-sway;
    background: radial-gradient(ellipse at 50% 50%, rgba(56, 220, 162, .58), rgba(28, 162, 172, .26) 36%, transparent 65%);
  }
  #codex-live-background .codex-aurora-band:nth-child(2) {
    top: 25%; left: -3%; --duration: 32s; --delay: -16s;
    background: radial-gradient(ellipse, rgba(67, 144, 216, .60), rgba(100, 88, 210, .23) 38%, transparent 65%);
  }
  #codex-live-background .codex-aurora-band:nth-child(3) {
    top: 42%; left: -35%; --duration: 38s; --delay: -24s;
    background: radial-gradient(ellipse, rgba(52, 195, 155, .40), transparent 62%);
  }
  @keyframes codex-aurora-sway {
    from { transform: translate3d(-5%, -8%, 0) rotate(-24deg) scaleY(.60); opacity: .65; }
    to { transform: translate3d(8%, 8%, 0) rotate(-8deg) scaleY(.90); opacity: 1; }
  }
  #codex-live-background .codex-light-bokeh {
    background: linear-gradient(130deg, #241c32, #1d2f3c 52%, #32252f);
  }
  #codex-live-background .codex-bokeh-orb {
    width: clamp(90px, var(--size, 16vw), 260px); aspect-ratio: 1;
    border-radius: 50%; animation-name: codex-bokeh-float;
    background: radial-gradient(circle, rgba(255, 255, 255, .20), var(--orb-color) 28%, transparent 68%);
  }
  @keyframes codex-bokeh-float {
    from { transform: translate3d(-25px, 25px, 0) scale(.85); opacity: .45; }
    to { transform: translate3d(45px, -60px, 0) scale(1.10); opacity: .85; }
  }
  #codex-live-background .codex-light-meteors {
    background: radial-gradient(ellipse at 70% 20%, #183148, #101a33 45%, #060c1a);
  }
  #codex-live-background .codex-meteor-stars {
    position: absolute; inset: 0; background-size: 100% 100%; opacity: .80;
  }
  #codex-live-background .codex-meteor-streak {
    width: 180px; height: 2px; opacity: 0; border-radius: 50%;
    background: linear-gradient(90deg, #e5f7ff, rgba(126, 202, 255, .60) 18%, transparent);
    animation: codex-meteor-fall var(--duration) linear var(--delay) infinite;
  }
  @keyframes codex-meteor-fall {
    0% { transform: rotate(-32deg) translateX(250px); opacity: 0; }
    2% { opacity: .90; }
    18% { transform: rotate(-32deg) translateX(-110vmax); opacity: 0; }
    100% { transform: rotate(-32deg) translateX(-110vmax); opacity: 0; }
  }
  @media (prefers-reduced-motion: reduce) {
    #codex-live-background .codex-light-layer { animation: none !important; }
  }
`;

async function findTarget() {
  const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
    signal: AbortSignal.timeout(1500),
  });
  const targets = await response.json();
  const exact = targets.find((item) => item.type === "page" && item.url === "app://-/index.html");
  if (exact) return exact;
  return targets.find((item) => {
    if (item.type !== "page") return false;
    try {
      const url = new URL(item.url);
      const route = url.searchParams.get("initialRoute");
      const mainRoute = route == null || route === "/" || /^\/(?:threads?|new|home|codex)(?:\/|$)/.test(route);
      return mainRoute && url.protocol === "app:" && url.hostname === "-" && url.pathname === "/index.html";
    } catch { return false; }
  });
}

async function connect() {
  const target = await findTarget();
  if (!target) throw new Error("找不到 Codex 主窗口");

  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });

  let nextID = 1;
  const pending = new Map();
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id == null) return;
    const callbacks = pending.get(message.id);
    if (!callbacks) return;
    pending.delete(message.id);
    if (message.error) callbacks.reject(new Error(message.error.message));
    else callbacks.resolve(message.result);
  });

  const command = (method, params = {}) => {
    const id = nextID++;
    socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  };

  const evaluate = async (expression) => {
    const response = await command("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (response.exceptionDetails) {
      const description = response.exceptionDetails.exception?.description ?? response.exceptionDetails.text;
      throw new Error(description);
    }
    return response.result?.value;
  };

  await command("Page.enable");
  await command("Page.setBypassCSP", { enabled: true });
  return { evaluate, socket };
}

function cleanupRenderer(restoreTheme) {
  if (window.__codexBgCleanupEffect) window.__codexBgCleanupEffect();
  delete window.__codexBgCleanupEffect;
  document.getElementById("codex-live-background")?.remove();
  document.getElementById("codex-live-effects-overlay")?.remove();
  document.getElementById("codex-live-background-style")?.remove();
  if (window.__codexBgObjectURL) URL.revokeObjectURL(window.__codexBgObjectURL);
  window.__codexBgObjectURL = null;
  window.__codexBgChunks = [];
  if (window.__codexBgResumePlayback) {
    document.removeEventListener("visibilitychange", window.__codexBgResumePlayback);
  }
  delete window.__codexBgResumePlayback;
  delete document.documentElement.dataset.codexLiveBackground;
  delete document.documentElement.dataset.codexLiveBackgroundKind;
  delete document.documentElement.dataset.codexBackgroundClarityMode;

  if (restoreTheme && Object.prototype.hasOwnProperty.call(window, "__codexBgPreviousTheme")) {
    if (window.__codexBgPreviousTheme) {
      document.documentElement.dataset.theme = window.__codexBgPreviousTheme;
    } else {
      delete document.documentElement.dataset.theme;
    }
    delete window.__codexBgPreviousTheme;
    delete document.documentElement.dataset.codexLiveTransparency;
    for (const name of [
      "--codex-main-alpha",
      "--codex-sidebar-alpha",
      "--codex-composer-alpha",
      "--codex-surface-alpha",
      "--codex-under-alpha",
      "--codex-shade-alpha",
      "--codex-main-blur",
      "--codex-sidebar-blur",
      "--codex-composer-blur",
      "--codex-asset-brightness",
      "--codex-asset-saturation",
    ]) document.documentElement.style.removeProperty(name);
  }
}

function setTransparencyRenderer(value, keepClear = false) {
  const transparency = Math.min(1, Math.max(.10, Number(value) || .70));
  const root = document.documentElement;
  const values = {
    "--codex-main-alpha": .82 - .86 * transparency,
    "--codex-sidebar-alpha": .88 - .86 * transparency,
    "--codex-composer-alpha": .94 - .50 * transparency,
    "--codex-surface-alpha": .82 - .85 * transparency,
    "--codex-under-alpha": .84 - .85 * transparency,
    "--codex-shade-alpha": keepClear ? .02 : .60 - .58 * transparency,
  };
  for (const [name, alpha] of Object.entries(values)) {
    root.style.setProperty(name, Math.min(.98, Math.max(.04, alpha)).toFixed(3));
  }
  root.style.setProperty("--codex-main-blur", (keepClear ? 0 : 18 * (1 - transparency)).toFixed(1) + "px");
  root.style.setProperty("--codex-sidebar-blur", (keepClear ? 0 : 22 * (1 - transparency)).toFixed(1) + "px");
  root.style.setProperty("--codex-composer-blur", (keepClear ? 0 : 18 * (1 - transparency)).toFixed(1) + "px");
  root.style.setProperty("--codex-asset-brightness", (keepClear ? 1.10 : .78 + .32 * transparency).toFixed(3));
  root.style.setProperty("--codex-asset-saturation", (keepClear ? 1.12 : .98 + .14 * transparency).toFixed(3));
  root.dataset.codexLiveTransparency = transparency.toFixed(2);
  root.dataset.codexBackgroundClarityMode = keepClear ? "clear" : "linked";
  return transparency;
}

function installThemeAndSurface(kind, css, transparency, keepClear) {
  if (!Object.prototype.hasOwnProperty.call(window, "__codexBgPreviousTheme")) {
    window.__codexBgPreviousTheme = document.documentElement.dataset.theme || "";
  }
  setTransparencyRenderer(transparency, keepClear);
  document.documentElement.dataset.theme = "dark";
  document.documentElement.dataset.codexLiveBackground = "true";
  document.documentElement.dataset.codexLiveBackgroundKind = kind;

  const background = document.createElement("div");
  background.id = "codex-live-background";
  document.body.prepend(background);

  const style = document.createElement("style");
  style.id = "codex-live-background-style";
  style.textContent = css;
  document.head.append(style);
  return background;
}

function installLightEffectRenderer(effect, css, transparency, keepClear) {
  const background = installThemeAndSurface(effect, css, transparency, keepClear);
  const stage = document.createElement("div");
  stage.className = "codex-light-stage codex-light-" + effect;
  background.append(stage);

  const addLayer = (className, properties = {}) => {
    const layer = document.createElement("div");
    layer.className = "codex-light-layer " + className;
    for (const [name, value] of Object.entries(properties)) layer.style.setProperty(name, value);
    stage.append(layer);
  };
  if (effect === "gradient" || effect === "aurora") {
    for (let index = 0; index < 3; index++) {
      addLayer(effect === "gradient" ? "codex-gradient-blob" : "codex-aurora-band");
    }
  } else if (effect === "bokeh") {
    const positions = [[4, 10], [30, 5], [63, 3], [82, 24], [12, 42], [46, 33],
      [70, 56], [27, 72], [3, 86], [52, 83], [86, 82], [93, 4]];
    const colors = ["rgba(230, 169, 118, .38)", "rgba(184, 131, 206, .40)", "rgba(98, 188, 206, .38)"];
    positions.forEach(([left, top], index) => addLayer("codex-bokeh-orb", {
      left: left + "%", top: top + "%", "--orb-color": colors[index % colors.length],
      "--size": (12 + index % 4 * 3) + "vw", "--duration": (24 + index * 2) + "s",
      "--delay": (-index * 3) + "s",
    }));
  } else if (effect === "meteors") {
    const stars = document.createElement("div");
    stars.className = "codex-meteor-stars";
    // Static vector stars are painted once and scale with the window; no canvas redraw.
    let circles = "";
    for (let index = 0; index < 140; index++) {
      circles += `<circle cx="${(index * 137.51) % 1000}" cy="${(index * 83.17) % 700}" r="${index % 9 === 0 ? 1.5 : .7}" opacity="${.3 + index % 6 * .1}"/>`;
    }
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 700" preserveAspectRatio="none"><g fill="#d2eaff">${circles}</g></svg>`;
    stars.style.backgroundImage = `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
    stage.append(stars);
    for (let index = 0; index < 6; index++) addLayer("codex-meteor-streak", {
      left: (30 + index * 14) + "%", top: (-5 + index * 10) + "%",
      "--duration": (10 + index * 2) + "s", "--delay": (-index * 3.7) + "s",
    });
  }

  const updateVisibility = () => {
    background.dataset.paused = String(document.visibilityState !== "visible");
  };
  document.addEventListener("visibilitychange", updateVisibility);
  updateVisibility();
  window.__codexBgCleanupEffect = () => {
    document.removeEventListener("visibilitychange", updateVisibility);
    for (const animation of background.getAnimations({ subtree: true })) animation.cancel();
  };
  return { effect, layerCount: stage.children.length, renderer: "css-compositor" };
}

function installEffectRenderer(effect, css, transparency, keepClear) {
  const background = installThemeAndSurface(effect, css, transparency, keepClear);
  const canvas = document.createElement("canvas");
  canvas.id = "codex-live-background-canvas";
  background.append(canvas);
  const context = canvas.getContext("2d", { alpha: false });
  const effectsCanvas = document.createElement("canvas");
  effectsCanvas.id = "codex-live-effects-overlay";
  effectsCanvas.style.opacity = effect === "particles" ? ".42" : ".58";
  background.append(effectsCanvas);
  const effectsContext = effectsCanvas.getContext("2d");

  let width = 1;
  let height = 1;
  let pixelRatio = 1;
  let animationFrame = 0;
  let alive = true;
  let items = [];

  const makeCosmosStar = (fresh = false) => ({
    x: (Math.random() - .5) * .95,
    y: (Math.random() - .5) * .95,
    z: fresh ? 1 : Math.random() * .96 + .04,
    glow: Math.random() * .48 + .52,
  });

  const makeParticle = () => ({
    x: Math.random() * width,
    y: Math.random() * height,
    vx: (Math.random() - .5) * .16,
    vy: (Math.random() - .5) * .16,
    radius: Math.random() * 1.5 + 1.15,
    phase: Math.random() * Math.PI * 2,
  });

  const resetItems = () => {
    if (effect === "cosmos") {
      const count = Math.min(360, Math.max(170, Math.round((width * height) / 5200)));
      items = Array.from({ length: count }, () => makeCosmosStar());
    } else {
      const count = Math.min(110, Math.max(58, Math.round((width * height) / 13500)));
      items = Array.from({ length: count }, makeParticle);
    }
  };

  const resize = () => {
    width = Math.max(1, window.innerWidth);
    height = Math.max(1, window.innerHeight);
    pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * pixelRatio);
    canvas.height = Math.round(height * pixelRatio);
    effectsCanvas.width = Math.round(width * pixelRatio);
    effectsCanvas.height = Math.round(height * pixelRatio);
    canvas.style.width = width + "px";
    canvas.style.height = height + "px";
    effectsCanvas.style.width = width + "px";
    effectsCanvas.style.height = height + "px";
    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    effectsContext.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    resetItems();
  };

  const drawCosmos = (now, delta) => {
    context.fillStyle = "#02040d";
    context.fillRect(0, 0, width, height);

    const driftX = Math.sin(now * .000055) * width * .08;
    const driftY = Math.cos(now * .000041) * height * .06;
    const nebulaA = context.createRadialGradient(
      width * .26 + driftX, height * .34 + driftY, 0,
      width * .26 + driftX, height * .34 + driftY, Math.max(width, height) * .68,
    );
    nebulaA.addColorStop(0, "rgba(78, 61, 230, .34)");
    nebulaA.addColorStop(.35, "rgba(38, 75, 166, .18)");
    nebulaA.addColorStop(1, "rgba(2, 4, 13, 0)");
    context.fillStyle = nebulaA;
    context.fillRect(0, 0, width, height);

    const nebulaB = context.createRadialGradient(
      width * .78 - driftX * .6, height * .62 - driftY, 0,
      width * .78 - driftX * .6, height * .62 - driftY, Math.max(width, height) * .56,
    );
    nebulaB.addColorStop(0, "rgba(10, 182, 210, .20)");
    nebulaB.addColorStop(.42, "rgba(87, 43, 164, .12)");
    nebulaB.addColorStop(1, "rgba(2, 4, 13, 0)");
    context.fillStyle = nebulaB;
    context.fillRect(0, 0, width, height);
    effectsContext.clearRect(0, 0, width, height);

    const centerX = width * .52;
    const centerY = height * .48;
    for (let index = 0; index < items.length; index++) {
      let star = items[index];
      const previousZ = star.z;
      star.z -= delta * .000045;
      const scale = 1 / Math.max(star.z, .02);
      const x = centerX + star.x * width * scale;
      const y = centerY + star.y * height * scale;
      if (star.z <= .018 || x < -30 || x > width + 30 || y < -30 || y > height + 30) {
        star = makeCosmosStar(true);
        items[index] = star;
        continue;
      }
      const previousScale = 1 / Math.max(previousZ, .02);
      const previousX = centerX + star.x * width * previousScale;
      const previousY = centerY + star.y * height * previousScale;
      const intensity = Math.min(1, (1 - star.z) * 1.32 + .12) * star.glow;
      effectsContext.beginPath();
      effectsContext.moveTo(previousX, previousY);
      effectsContext.lineTo(x, y);
      effectsContext.strokeStyle = "rgba(155, 207, 255, " + (intensity * .82) + ")";
      effectsContext.lineWidth = Math.max(.65, (1 - star.z) * 2.8);
      effectsContext.stroke();
      effectsContext.beginPath();
      effectsContext.arc(x, y, Math.max(.72, (1 - star.z) * 3.05), 0, Math.PI * 2);
      effectsContext.fillStyle = "rgba(232, 243, 255, " + Math.min(.98, intensity + .28) + ")";
      effectsContext.shadowColor = "rgba(122, 186, 255, .85)";
      effectsContext.shadowBlur = 8;
      effectsContext.fill();
      effectsContext.shadowBlur = 0;
    }
  };

  const drawParticles = (now, delta) => {
    const backgroundGradient = context.createLinearGradient(0, 0, width, height);
    backgroundGradient.addColorStop(0, "#04071a");
    backgroundGradient.addColorStop(.48, "#10143b");
    backgroundGradient.addColorStop(1, "#071b2a");
    context.fillStyle = backgroundGradient;
    context.fillRect(0, 0, width, height);

    const halo = context.createRadialGradient(
      width * (.5 + Math.sin(now * .00011) * .12),
      height * (.46 + Math.cos(now * .00009) * .10),
      0,
      width * .5, height * .5, Math.max(width, height) * .65,
    );
    halo.addColorStop(0, "rgba(94, 78, 255, .19)");
    halo.addColorStop(.5, "rgba(26, 203, 229, .08)");
    halo.addColorStop(1, "rgba(0, 0, 0, 0)");
    context.fillStyle = halo;
    context.fillRect(0, 0, width, height);
    effectsContext.clearRect(0, 0, width, height);

    const speed = Math.min(delta, 36);
    for (const particle of items) {
      particle.x += particle.vx * speed;
      particle.y += particle.vy * speed;
      if (particle.x < -20) particle.x = width + 20;
      if (particle.x > width + 20) particle.x = -20;
      if (particle.y < -20) particle.y = height + 20;
      if (particle.y > height + 20) particle.y = -20;
    }

    const connectionDistance = Math.min(155, Math.max(110, width / 10));
    const connectionDistanceSquared = connectionDistance * connectionDistance;
    for (let first = 0; first < items.length; first++) {
      for (let second = first + 1; second < items.length; second++) {
        const dx = items[first].x - items[second].x;
        const dy = items[first].y - items[second].y;
        const distanceSquared = dx * dx + dy * dy;
        if (distanceSquared >= connectionDistanceSquared) continue;
        const alpha = (1 - distanceSquared / connectionDistanceSquared) * .34;
        effectsContext.beginPath();
        effectsContext.moveTo(items[first].x, items[first].y);
        effectsContext.lineTo(items[second].x, items[second].y);
        effectsContext.strokeStyle = "rgba(112, 203, 255, " + alpha + ")";
        effectsContext.lineWidth = .8;
        effectsContext.stroke();
      }
    }

    for (const particle of items) {
      const pulse = .72 + Math.sin(now * .0014 + particle.phase) * .28;
      effectsContext.beginPath();
      effectsContext.arc(particle.x, particle.y, particle.radius * (1 + pulse * .24), 0, Math.PI * 2);
      effectsContext.fillStyle = "rgba(178, 226, 255, " + (.5 + pulse * .42) + ")";
      effectsContext.shadowColor = "rgba(77, 185, 255, .8)";
      effectsContext.shadowBlur = 12;
      effectsContext.fill();
      effectsContext.shadowBlur = 0;
    }
  };

  let previousTime = performance.now();
  const draw = (now) => {
    if (!alive) return;
    const delta = Math.min(45, Math.max(0, now - previousTime));
    previousTime = now;
    if (effect === "cosmos") drawCosmos(now, delta);
    else drawParticles(now, delta);
    animationFrame = requestAnimationFrame(draw);
  };

  resize();
  window.addEventListener("resize", resize);
  window.__codexBgCleanupEffect = () => {
    alive = false;
    cancelAnimationFrame(animationFrame);
    window.removeEventListener("resize", resize);
    effectsCanvas.remove();
  };
  draw(performance.now());
  return { effect, itemCount: items.length, width, height };
}

function installVideoRenderer(mimeType, css, transparency, keepClear) {
  const parts = window.__codexBgChunks.map((encoded) => {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
    return bytes;
  });
  window.__codexBgChunks = [];
  const objectURL = URL.createObjectURL(new Blob(parts, { type: mimeType }));
  window.__codexBgObjectURL = objectURL;

  const background = installThemeAndSurface("video", css, transparency, keepClear);
  const video = document.createElement("video");
  video.id = "codex-live-background-video";
  video.src = objectURL;
  video.autoplay = true;
  video.loop = true;
  video.muted = true;
  video.playsInline = true;
  background.append(video);

  window.__codexBgResumePlayback = () => {
    if (document.visibilityState === "visible") video.play().catch(() => {});
  };
  document.addEventListener("visibilitychange", window.__codexBgResumePlayback);
  video.play().catch(() => {});
  return true;
}

function installImageRenderer(mimeType, css, transparency, keepClear) {
  const parts = window.__codexBgChunks.map((encoded) => {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
    return bytes;
  });
  window.__codexBgChunks = [];
  const objectURL = URL.createObjectURL(new Blob(parts, { type: mimeType }));
  window.__codexBgObjectURL = objectURL;

  const background = installThemeAndSurface("image", css, transparency, keepClear);
  const image = document.createElement("img");
  image.id = "codex-live-background-image";
  image.src = objectURL;
  image.alt = "";
  image.decoding = "async";
  background.append(image);
  return true;
}

function mimeTypeFor(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case ".webm": return "video/webm";
    case ".m4v": return "video/x-m4v";
    case ".mov": return "video/quicktime";
    default: return "video/mp4";
  }
}

function imageMimeTypeFor(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case ".png": return "image/png";
    case ".webp": return "image/webp";
    case ".gif": return "image/gif";
    case ".heic":
    case ".heif": return "image/heic";
    default: return "image/jpeg";
  }
}

async function runStatus() {
  const client = await connect();
  try {
    const result = await client.evaluate(`(() => ({
      active: document.documentElement.dataset.codexLiveBackground === "true"
        && document.getElementById("codex-live-background") != null,
      kind: document.documentElement.dataset.codexLiveBackgroundKind || "",
    }))()`);
    console.log(result.active ? "active" : "inactive");
  } finally {
    client.socket.close();
  }
}

async function runRemove() {
  const client = await connect();
  try {
    await client.evaluate(`(${cleanupRenderer.toString()})(true)`);
    console.log("removed");
  } finally {
    client.socket.close();
  }
}

async function applyEffect() {
  if (!new Set(["cosmos", "particles", ...lightweightEffects]).has(assetPath)) {
    throw new Error("未知的动态效果");
  }
  const lightweight = lightweightEffects.has(assetPath);
  const renderer = lightweight ? installLightEffectRenderer : installEffectRenderer;
  const css = sharedCSS + (lightweight ? lightweightCSS : "");
  const client = await connect();
  try {
    await client.evaluate(`(${cleanupRenderer.toString()})(false)`);
    const result = await client.evaluate(
      `(() => {
        const setTransparencyRenderer = ${setTransparencyRenderer.toString()};
        const installThemeAndSurface = ${installThemeAndSurface.toString()};
        return (${renderer.toString()})(${JSON.stringify(assetPath)}, ${JSON.stringify(css)}, ${JSON.stringify(initialTransparency)}, ${JSON.stringify(keepBackgroundClear)});
      })()`,
    );
    console.log(JSON.stringify(result));
  } finally {
    client.socket.close();
  }
}

async function applyVideo() {
  if (!assetPath) throw new Error("没有选择视频文件");
  const info = fs.statSync(assetPath);
  if (!info.isFile()) throw new Error("选择的路径不是文件");
  if (info.size > maxVideoBytes) throw new Error("视频超过 200 MB，请换一个较短的循环视频");

  const client = await connect();
  try {
    await client.evaluate(`(${cleanupRenderer.toString()})(false)`);
    await client.evaluate("window.__codexBgChunks = []");
    const bytes = fs.readFileSync(assetPath);
    const chunkSize = 384 * 1024;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      const encoded = bytes.subarray(offset, offset + chunkSize).toString("base64");
      await client.evaluate(`window.__codexBgChunks.push(${JSON.stringify(encoded)})`);
    }

    await client.evaluate(
      `(() => {
        const setTransparencyRenderer = ${setTransparencyRenderer.toString()};
        const installThemeAndSurface = ${installThemeAndSurface.toString()};
        return (${installVideoRenderer.toString()})(${JSON.stringify(mimeTypeFor(assetPath))}, ${JSON.stringify(sharedCSS)}, ${JSON.stringify(initialTransparency)}, ${JSON.stringify(keepBackgroundClear)});
      })()`,
    );
    await new Promise((resolve) => setTimeout(resolve, 650));
    const result = await client.evaluate(`(() => {
      const element = document.getElementById("codex-live-background-video");
      if (!element) throw new Error("视频背景没有创建成功");
      if (element.readyState < 2 && element.error) {
        throw new Error(element.error.message || "视频没有开始播放");
      }
      return {
        width: element.videoWidth,
        height: element.videoHeight,
        readyState: element.readyState,
        paused: element.paused,
      };
    })()`);
    console.log(JSON.stringify(result));
  } finally {
    client.socket.close();
  }
}

async function applyImage() {
  if (!assetPath) throw new Error("没有选择图片文件");
  const info = fs.statSync(assetPath);
  if (!info.isFile()) throw new Error("选择的路径不是文件");
  if (info.size > maxImageBytes) throw new Error("图片超过 80 MB，请换一张较小的图片");

  const client = await connect();
  try {
    await client.evaluate(`(${cleanupRenderer.toString()})(false)`);
    await client.evaluate("window.__codexBgChunks = []");
    const bytes = fs.readFileSync(assetPath);
    const chunkSize = 384 * 1024;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      const encoded = bytes.subarray(offset, offset + chunkSize).toString("base64");
      await client.evaluate(`window.__codexBgChunks.push(${JSON.stringify(encoded)})`);
    }

    await client.evaluate(
      `(() => {
        const setTransparencyRenderer = ${setTransparencyRenderer.toString()};
        const installThemeAndSurface = ${installThemeAndSurface.toString()};
        return (${installImageRenderer.toString()})(${JSON.stringify(imageMimeTypeFor(assetPath))}, ${JSON.stringify(sharedCSS)}, ${JSON.stringify(initialTransparency)}, ${JSON.stringify(keepBackgroundClear)});
      })()`,
    );
    await new Promise((resolve) => setTimeout(resolve, 350));
    const result = await client.evaluate(`(() => {
      const element = document.getElementById("codex-live-background-image");
      if (!element) throw new Error("图片背景没有创建成功");
      if (element.complete && element.naturalWidth === 0) throw new Error("当前图片格式无法显示");
      return { width: element.naturalWidth, height: element.naturalHeight, complete: element.complete };
    })()`);
    console.log(JSON.stringify(result));
  } catch (error) {
    await client.evaluate(`(${cleanupRenderer.toString()})(true)`).catch(() => {});
    throw error;
  } finally {
    client.socket.close();
  }
}

async function setTransparency() {
  const value = Number(transparencyText);
  if (!Number.isFinite(value)) throw new Error("透明度参数无效");
  const client = await connect();
  try {
    const result = await client.evaluate(`(${setTransparencyRenderer.toString()})(${JSON.stringify(value)}, ${JSON.stringify(keepBackgroundClear)})`);
    console.log(Number(result).toFixed(2));
  } finally {
    client.socket.close();
  }
}

try {
  if (action === "status") await runStatus();
  else if (action === "apply-effect") await applyEffect();
  else if (action === "apply-video" || action === "apply") await applyVideo();
  else if (action === "apply-image") await applyImage();
  else if (action === "set-transparency") await setTransparency();
  else if (action === "remove") await runRemove();
  else throw new Error(`未知操作：${action}`);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
