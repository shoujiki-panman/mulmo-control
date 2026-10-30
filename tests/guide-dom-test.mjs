// v10 のメニュー構造とイベントを再現し、ガイド本体をそのまま動かす。
// 最小の DOM: title から data-tip への移行、body に移ったメニュー、名前の span を検査。
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

class Element {
  constructor(tag = "div", attrs = {}, text = "") {
    this.tagName = tag;
    this.attrs = new Map(Object.entries(attrs));
    this.dataset = new Proxy({}, {
      get: (_, key) => this.getAttribute(`data-${String(key).replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`) ?? undefined,
      set: (_, key, value) => { this.setAttribute(`data-${String(key).replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`, value); return true; },
      has: (_, key) => this.hasAttribute(`data-${String(key).replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`),
      deleteProperty: (_, key) => { this.removeAttribute(`data-${String(key).replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`); return true; },
    });
    this.children = [];
    this.childNodes = [];
    this.style = {};
    this.textContent = text;
    this.listeners = {};
  }
  getAttribute(key) { return this.attrs.get(key) ?? null; }
  hasAttribute(key) { return this.attrs.has(key); }
  setAttribute(key, value) { this.attrs.set(key, String(value)); }
  removeAttribute(key) { this.attrs.delete(key); }
  matches(selector) {
    return selector.split(",").some((part) => {
      if (part === "pre[data-code-block]") return this.tagName === "pre" && this.hasAttribute("data-code-block");
      if (part === "button") return this.tagName === "button";
      if (part === ".truncate") return this.getAttribute("class") === "truncate";
      const match = part.match(/^\[([^=\]]+)(?:="([^"]*)")?\]$/);
      return match && this.hasAttribute(match[1]) && (match[2] === undefined || this.getAttribute(match[1]) === match[2]);
    });
  }
  closest(selector) { return this.matches(selector) ? this : this.parentElement?.closest(selector) ?? null; }
  querySelector(selector) {
    for (const child of this.children) {
      if (child.matches(selector)) return child;
      const found = child.querySelector(selector);
      if (found) return found;
    }
    return null;
  }
  append(...children) { for (const child of children) { child.parentElement = this; this.children.push(child); this.childNodes.push(child); } }
  appendChild(child) { this.append(child); }
  addEventListener(type, fn) { this.listeners[type] = fn; }
  getBoundingClientRect() { return { width: 280, height: 100 }; }
}
class Button extends Element { constructor(attrs = {}) { super("button", attrs); } }
const body = new Element();
const listeners = {};
const document = {
  title: "mulmoterminal", body,
  createElement: (tag) => tag === "button" ? new Button() : new Element(tag),
  getElementById: (id) => {
    const visit = (node) => node.id === id ? node : node.children.map(visit).find(Boolean);
    return visit(body) ?? null;
  },
  querySelector: (selector) => body.querySelector(selector),
  querySelectorAll: () => [],
  addEventListener: (type, fn) => { listeners[type] = fn; },
};
const box = vm.createContext({
  document, Element, HTMLButtonElement: Button, Node: { TEXT_NODE: 3 },
  window: { innerWidth: 1000, innerHeight: 800, addEventListener: () => {} },
  localStorage: { getItem: () => null, setItem: () => {} },
  fetch: async () => ({ ok: false }), setInterval: () => {}, setTimeout: () => {},
});
vm.runInContext(readFileSync(new URL("../guide/mulmoterminal-guide.js", import.meta.url), "utf8"), box);
const hover = (node, type = "mousemove") => listeners[type]({ target: node, clientX: 20, clientY: 20 });
const shown = () => {
  const bubble = document.getElementById("mtg-bubble");
  return bubble?.style.display === "block" ? bubble.querySelector('[data-part="what"]').textContent : null;
};
const menu = new Element("div", { role: "menu", "data-testid": "skill-menu" });
const item = new Button({ role: "menuitem", "data-tip": "Help with MulmoTerminal." });
const icon = new Element("span", { class: "material-symbols-outlined" }, "bolt");
const label = new Element("span", { class: "truncate" }, "mulmoterminal-help");
item.append(icon, label); menu.append(item); body.append(menu);
hover(label, "pointerover");
assert.match(shown(), /相談窓口/);
assert.equal(item.hasAttribute("data-tip"), false, "上流の吹き出しを出さない");
hover(icon);
assert.match(shown(), /相談窓口/, "名前が span にあっても同梱の日本語を出し続ける");
hover(body);
assert.equal(shown(), null);
assert.equal(item.getAttribute("data-tip"), "Help with MulmoTerminal.");
label.textContent = "example-notes";
item.setAttribute("data-tip", "記録を整理します。週末に使います。");
hover(label);
assert.equal(shown(), "記録を整理します。週末に使います。", "本人のスキルはその場の説明");
item.setAttribute("data-tip", "更新された説明");
hover(body);
assert.equal(item.getAttribute("data-tip"), "更新された説明", "上流による更新を戻さない");
menu.setAttribute("data-testid", "run-menu");
hover(label);
assert.equal(shown(), null, "Run のコマンドをスキルの説明にしない");
const skillButton = new Button({ "aria-haspopup": "menu", "data-tip": "今のセッションでスキルを実行" });
hover(skillButton);
assert.match(shown(), /スキル/);
const history = new Button({ "data-testid": "cell-pane-menu-transcript", "data-tip": "Conversation" });
hover(history, "pointerover");
assert.match(shown(), /会話/);
assert.equal(skillButton.getAttribute("data-tip"), "今のセッションでスキルを実行");
const copy = new Button({ "aria-label": "Copy code", title: "Copy code" });
hover(copy);
assert.match(shown(), /コピー/);
assert.equal(copy.hasAttribute("title"), false);
document.getElementById("mtg-toggle").listeners.click();
assert.equal(shown(), null);
assert.equal(copy.getAttribute("title"), "Copy code", "ガイドを切ったら標準の説明を戻す");
hover(history);
assert.equal(shown(), null, "オフのときは表示しない");
process.stdout.write("画面ガイド: v10 の履歴・スキル・コピー、説明の退避と復元、オン／オフを確認\n");

// プレビュー用スクリプト: 親からの真偽値だけを受け、コピー処理には触れない。
const previewListeners = {};
const parentMessages = [];
const parent = { postMessage: (message) => parentMessages.push(message) };
const previewBox = vm.createContext({
  document, Element, parent, innerWidth: 800, innerHeight: 600,
  window: { addEventListener: (type, fn) => { previewListeners[type] = fn; } },
});
vm.runInContext(readFileSync(new URL("../guide/mulmoterminal-preview-guide.js", import.meta.url), "utf8"), previewBox);
assert.equal(parentMessages[0].source, "mulmo-preview-guide-ready");
const pre = new Element("pre", { "data-code-block": "0" });
const previewCopy = new Button({ title: "Copy code" });
previewCopy.previousElementSibling = pre;
body.append(pre, previewCopy);
hover(previewCopy);
assert.equal(document.getElementById("mtg-preview-bubble"), null, "親の返事を待ってから表示する");
previewListeners.message({ source: {}, data: { source: "mulmo-preview-guide-host", on: true } });
hover(previewCopy);
assert.equal(document.getElementById("mtg-preview-bubble"), null, "ほかの窓のオンを受けない");
previewListeners.message({ source: parent, data: { source: "mulmo-preview-guide-host", on: true } });
hover(previewCopy);
const previewBubble = document.getElementById("mtg-preview-bubble");
assert.match(previewBubble.textContent, /ファイルの内容/);
assert.match(previewBubble.textContent, /確認画面/);
assert.equal(previewCopy.hasAttribute("title"), false);
previewListeners.message({ source: parent, data: { source: "mulmo-preview-guide-host", on: false } });
assert.equal(previewBubble.style.display, "none");
assert.equal(previewCopy.getAttribute("title"), "Copy code");
assert.equal(previewCopy.listeners.click, undefined, "コピーのクリック処理を追加・変更しない");
process.stdout.write("プレビュー: 親だけからオン／オフを受け、コピーの説明と標準 title の復元を確認\n");
