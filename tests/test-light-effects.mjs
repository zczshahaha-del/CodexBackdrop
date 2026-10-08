import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);
const port = Number(process.argv[2] || 9224);
const screenshotDirectory = process.argv[3] && !process.argv[3].startsWith("--") ? process.argv[3] : undefined;
const helper = path.join(import.meta.dirname, "../src/helper.mjs");
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find(item => item.type === "page" && item.url === "app://-/index.html");
assert.ok(target, "Codex main window must be connected");
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});
let nextID = 0;
const pending = new Map();
socket.addEventListener("message", event => {
  const message = JSON.parse(event.data);
  const callbacks = pending.get(message.id);
  if (!callbacks) return;
  pending.delete(message.id);
  if (message.error) callbacks.reject(new Error(message.error.message));
  else callbacks.resolve(message.result);
});
const command = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++nextID;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});
const evaluate = async expression => {
  const result = await command("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
  return result.result.value;
};
const apply = async (action, value, amount = "0.85", clarity = "clear") => {
  const result = await run(process.execPath, [helper, action, String(port), value, amount, clarity]);
  return result.stdout.trim();
};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const before = await evaluate(`({
  kind: document.documentElement.dataset.codexLiveBackgroundKind,
  amount: document.documentElement.dataset.codexLiveTransparency || '0.70',
  clarity: document.documentElement.dataset.codexBackgroundClarityMode || 'linked'
})`);
const builtinEffects = ["gradient", "aurora", "bokeh", "meteors", "cosmos", "particles"];
if (!builtinEffects.includes(before.kind)) {
  socket.close();
  throw new Error("测试前请先从菜单选择一个内置效果，避免改变照片或视频背景。");
}
try {
  for (const [effect, count] of [["gradient", 3], ["aurora", 3], ["bokeh", 12], ["meteors", 7]]) {
    await apply("apply-effect", effect);
    await sleep(400);
    const state = await evaluate(`(() => {
      const bg = document.getElementById('codex-live-background');
      const layer = bg.querySelector('.codex-light-layer');
      return {kind: document.documentElement.dataset.codexLiveBackgroundKind,
        backgrounds: document.querySelectorAll('#codex-live-background').length,
        styles: document.querySelectorAll('#codex-live-background-style').length,
        layers: bg.querySelector('.codex-light-stage').children.length,
        canvases: bg.querySelectorAll('canvas').length,
        animations: bg.getAnimations({subtree:true}).map(a=>({state:a.playState,time:a.currentTime})),
        transform: getComputedStyle(layer).transform,
        background: getComputedStyle(bg.querySelector('.codex-light-stage')).backgroundImage,
        svgStars: bg.querySelector('.codex-meteor-stars')?.style.backgroundImage.startsWith('url("data:image/svg+xml,') ?? false};
    })()`);
    assert.equal(state.kind, effect);
    assert.equal(state.backgrounds, 1);
    assert.equal(state.styles, 1);
    assert.equal(state.layers, count);
    assert.equal(state.canvases, 0);
    assert.ok(state.animations.length > 0 && state.animations.every(a => a.state === "running"));
    assert.notEqual(state.background, "none");
    if (effect === "meteors") assert.equal(state.svgStars, true);
    await sleep(400);
    const moved = await evaluate(`getComputedStyle(document.querySelector('#codex-live-background .codex-light-layer')).transform`);
    assert.notEqual(moved, state.transform, effect + " must move");
    const paused = await evaluate(`(() => {
      Object.defineProperty(document, 'visibilityState', {configurable:true,value:'hidden'});
      try {
        document.dispatchEvent(new Event('visibilitychange'));
        return document.getElementById('codex-live-background').getAnimations({subtree:true}).map(a=>a.playState);
      } finally {
        delete document.visibilityState;
        document.dispatchEvent(new Event('visibilitychange'));
      }
    })()`);
    assert.ok(paused.length > 0 && paused.every(value => value === "paused"));
    if (screenshotDirectory) {
      const capture = await command("Page.captureScreenshot", { format: "png" });
      fs.writeFileSync(path.join(screenshotDirectory, effect + ".png"), Buffer.from(capture.data, "base64"));
    }
    console.log(JSON.stringify({ effect, layers: state.layers, animations: state.animations.length, canvas: 0, moved: true, pausesWhenHidden: true }));
  }
  await command("Emulation.setEmulatedMedia", {features:[{name:"prefers-reduced-motion",value:"reduce"}]});
  assert.equal(await evaluate(`document.getElementById('codex-live-background').getAnimations({subtree:true}).length`), 0);
  await command("Emulation.setEmulatedMedia", {features:[]});
  await apply("apply-effect", "particles");
  assert.equal(await evaluate(`document.getElementById('codex-live-background').querySelectorAll('canvas').length`), 2);
  await apply("apply-effect", "gradient");
  assert.equal(await evaluate(`document.querySelectorAll('#codex-live-effects-overlay').length`), 0);
  const imagePath = path.join(import.meta.dirname, "../assets/AppIcon.png");
  const imageWidth = fs.readFileSync(imagePath).readUInt32BE(16);
  await apply("apply-image", imagePath);
  assert.equal(await evaluate(`document.getElementById('codex-live-background-image').naturalWidth`), imageWidth);
  assert.equal(await evaluate(`document.getElementById('codex-live-background').getAnimations({subtree:true}).length`), 0);
  await apply("apply-effect", "gradient");
  await apply("set-transparency", "0.20", "clear");
  const low = await evaluate(`document.documentElement.style.getPropertyValue('--codex-main-alpha')`);
  await apply("set-transparency", "0.95", "clear");
  const high = await evaluate(`document.documentElement.style.getPropertyValue('--codex-main-alpha')`);
  assert.ok(Number(low) > Number(high));
  assert.equal(await evaluate(`document.getElementById('codex-live-background').querySelectorAll('canvas,img,video').length`), 0);
  console.log(JSON.stringify({ reducedMotion: true, particles: true, image: true, cleanup: true, slider: { low, high } }));
  if (process.argv.includes("--restore")) {
    await run(process.execPath, [helper, "remove", String(port)]);
    await sleep(6000);
    const restored = await evaluate(`({
      active: document.documentElement.dataset.codexLiveBackground,
      kind: document.documentElement.dataset.codexLiveBackgroundKind,
      amount: document.documentElement.dataset.codexLiveTransparency,
      clarity: document.documentElement.dataset.codexBackgroundClarityMode
    })`);
    assert.equal(restored.active, "true");
    assert.equal(restored.kind, before.kind);
    assert.equal(restored.amount, before.amount);
    assert.equal(restored.clarity, before.clarity);
    console.log(JSON.stringify({ automaticRestoration: restored }));
  }
} finally {
  await command("Emulation.setEmulatedMedia", {features:[]}).catch(() => {});
  await apply("apply-effect", before.kind, before.amount, before.clarity).catch(error => console.error("Restore failed: " + error.message));
  socket.close();
}
