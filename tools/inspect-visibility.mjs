const port = Number(process.argv[2] || "9224");
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === "page" && item.url === "app://-/index.html");
if (!target) throw new Error("没有找到 Codex 页面");

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});

const id = 1;
socket.send(JSON.stringify({
  id,
  method: "Runtime.evaluate",
  params: {
    returnByValue: true,
    expression: `(() => {
      const main = [...document.querySelectorAll('#root [class*="_MainContentSurface_"]')].find(el=>el.getBoundingClientRect().width>0) || document.querySelector('#root main.flex.h-full');
      const asset = document.querySelector('#codex-live-background-image, #codex-live-background-video');
      return {
        value: document.documentElement.dataset.codexLiveTransparency || '',
        kind: document.getElementById('codex-live-background-image') ? 'image' : document.getElementById('codex-live-background-video') ? 'video' : 'effect',
        clarityMode: document.documentElement.dataset.codexBackgroundClarityMode || null,
        shadeAlpha: document.documentElement.style.getPropertyValue('--codex-shade-alpha').trim(),
        mainBackground: main ? getComputedStyle(main).backgroundColor : null,
        mainBlur: main ? getComputedStyle(main).backdropFilter : null,
        assetFilter: asset ? getComputedStyle(asset).filter : null,
        modernSurface: getComputedStyle(document.getElementById('root')).getPropertyValue('--color-surface').trim(),
        chatBackground: document.querySelector('#root .thread-pane') ? getComputedStyle(document.querySelector('#root .thread-pane')).backgroundColor : null,
        effectLayerParent: document.getElementById('codex-live-effects-overlay')?.parentElement?.id || null,
      };
    })()`,
  },
}));

const result = await new Promise((resolve, reject) => {
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    if (message.error) reject(new Error(message.error.message));
    else resolve(message.result.result.value);
  });
  socket.addEventListener("error", reject, { once: true });
});

socket.close();
console.log(JSON.stringify(result));
