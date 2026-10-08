import fs from "node:fs";

const port = Number(process.argv[2] || 9224);
const screenshot = process.argv[3];
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === "page" && item.url === "app://-/index.html");
if (!target) throw new Error("没有找到 Codex 主窗口");
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});
let nextID = 0;
const pending = new Map();
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (!pending.has(message.id)) return;
  const { resolve, reject } = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) reject(new Error(message.error.message));
  else resolve(message.result);
});
const command = (method, params) => new Promise((resolve, reject) => {
  const id = ++nextID;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});
try {
  const result = await command("Runtime.evaluate", {
    returnByValue: true,
    expression: `(() => {
      const describe = (element) => {
        const s = getComputedStyle(element), r = element.getBoundingClientRect();
        return {tag:element.tagName, className:element.className, id:element.id,
          background:s.backgroundColor, color:s.color, opacity:s.opacity,
          zIndex:s.zIndex, position:s.position, blur:s.backdropFilter,
          rect:{x:r.x,y:r.y,width:r.width,height:r.height},
          vars:Object.fromEntries(['--app-color-background-surface','--app-color-text-foreground',
            '--color-text','--color-text-primary','--color-text-placeholder','--color-surface',
            '--color-token-text-primary','--color-token-bg-primary','--color-token-text-secondary']
            .map(k=>[k,s.getPropertyValue(k).trim()]))};
      };
      const visible = (element) => {const r=element.getBoundingClientRect(); return r.width>0 && r.height>0 && r.bottom>0 && r.top<innerHeight;};
      const inputs = [...document.querySelectorAll('textarea, [contenteditable="true"]')].filter(visible);
      const rootStyles=getComputedStyle(document.getElementById('root'));
      return {htmlClass:document.documentElement.className,htmlDataset:{...document.documentElement.dataset},
        bodyClass:document.body.className, root:describe(document.getElementById('root')),
        colorTokens:Object.fromEntries([...rootStyles].filter(k=>/^--color-(surface|token-(bg-|main-surface|side-bar)|background-(panel|composer-surface))/.test(k)).map(k=>[k,rootStyles.getPropertyValue(k).trim()])),
        largePaintedElements:[...document.querySelectorAll('#root *')].filter(el=>{const r=el.getBoundingClientRect();return visible(el)&&r.width>400&&r.height>200&&getComputedStyle(el).backgroundColor!=='rgba(0, 0, 0, 0)';}).map(el=>({className:el.className,background:getComputedStyle(el).backgroundColor})).slice(0,20),
        surfaces:[...document.querySelectorAll('#root .bg-surface, #root .bg-surface-under, #root [class*="MainContent"], #root header')].filter(visible).slice(0,12).map(describe),
        layers:[...document.querySelectorAll('#codex-live-background, #codex-live-effects-overlay, main, aside, [class*="_MainContentSurface_"], [class*="_ComposerLayoutRoot_"]')].filter(visible).map(describe),
        inputs:inputs.map(el=>({element:describe(el),placeholderColor:getComputedStyle(el,'::placeholder').color,
          placeholders:[...el.querySelectorAll('p, span, [data-placeholder]')].slice(0,6).map(node=>({tag:node.tagName,className:node.className,hasPlaceholder:node.hasAttribute('data-placeholder'),beforeColor:getComputedStyle(node,'::before').color,color:getComputedStyle(node).color})),
          parents:[el.parentElement,el.parentElement?.parentElement,el.parentElement?.parentElement?.parentElement].filter(Boolean).map(describe)}))};
    })()`,
  });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
  console.log(JSON.stringify(result.result.value));
  if (screenshot) {
    const capture = await command("Page.captureScreenshot", { format: "png" });
    fs.writeFileSync(screenshot, Buffer.from(capture.data, "base64"));
  }
} finally { socket.close(); }
