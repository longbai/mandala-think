"use strict";

const byId = (id) => document.getElementById(id);
const openButton = byId("open");
const input = byId("file");
const grid = byId("grid");
const overlay = byId("drop-overlay");
const dialog = byId("image-dialog");
const fullImage = byId("full-image");
const status = byId("status");
const trail = byId("trail");

// Row-major file IDs. In memology.mandala, each chapter's sections 01–08
// use IDs 7, 6, 3, 0, 1, 2, 5, 8, matching the official numbered grid.
// The center displays the current node.
const POSITIONS = [0, 1, 2, 3, null, 5, 6, 7, 8];
const POSITION_LABELS = ["左上", "上方", "右上", "左侧", "中心", "右侧", "左下", "下方", "右下"];

const demoNode = (id, text, nodes = []) => ({
  id, text, images: [], children: new Map(nodes.map((item) => [item.id, item])),
});
const demo = demoNode(9, "设计我的一周\n把想做的事放到周围八格，再把需要细化的想法展开。", [
  demoNode(0, "学习", [
    demoNode(1, "阅读\n周三留出半小时读完一章。"),
    demoNode(3, "记录\n给读过的内容写一张笔记。", [
      demoNode(5, "回顾\n周末整理这周最有启发的想法。"),
    ]),
    demoNode(7, "练习\n选一个概念，用自己的话解释。"),
  ]),
  demoNode(1, "工作\n先确定一件最需要完成的事。"),
  demoNode(2, "健康\n安排两次散步。"),
  demoNode(3, "家庭\n留一个晚上一起吃饭。"),
  demoNode(5, "创作", [
    demoNode(1, "收集素材\n把本周遇到的灵感先记下来。"),
    demoNode(5, "写初稿\n给自己留一段完整的时间。"),
  ]),
  demoNode(6, "整理\n处理桌面和下载目录里积攒的东西。"),
  demoNode(7, "朋友\n约一位朋友聊聊近况。"),
  demoNode(8, "休息\n留一段没有安排的时间。"),
]);

let root = demo;
let fileName = "示例九宫格";
let stack = [root];
let selected = root;
let activeLoad = 0;
const urls = new Map();

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function title(node) {
  const [first, second] = node.text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (!first) return "";
  // A standalone section or chapter number is followed by its actual heading.
  const heading = second && /^(?:[0-9０-９]+|第[0-9０-９]+章)$/.test(first)
    ? `${first} ${second}`
    : first;
  return heading.slice(0, 52) + (heading.length > 52 ? "…" : "");
}

function label(node) {
  return title(node) || (node === root ? fileName.replace(/\.mandala$/i, "") : `格子 ${node.id}`);
}

function urlFor(blob) {
  if (!urls.has(blob)) urls.set(blob, URL.createObjectURL(blob));
  return urls.get(blob);
}

function current() {
  return stack[stack.length - 1];
}

function showLayer(index) {
  stack = stack.slice(0, index + 1);
  selected = current();
  render();
  focusCenter();
}

function focusCenter() {
  grid.querySelector(".center")?.focus({ preventScroll: true });
}

function openBranch(node) {
  stack.push(node);
  selected = node;
  render();
  focusCenter();
}

function renderTrail() {
  const crumbs = [];
  stack.forEach((node, index) => {
    if (index) crumbs.push(element("span", "crumb-divider", "›"));
    if (index === stack.length - 1) {
      const crumb = element("span", "crumb-current", node === root ? "根层" : label(node));
      crumb.setAttribute("aria-current", "location");
      crumbs.push(crumb);
      return;
    }
    const button = element("button", "crumb", node === root ? "根层" : label(node));
    button.type = "button";
    button.addEventListener("click", () => showLayer(index));
    crumbs.push(button);
  });
  trail.replaceChildren(...crumbs);
}

function renderCell(node, position) {
  const isCenter = position === 4;
  const hasText = Boolean(node?.text.trim());
  const hasImage = Boolean(node?.images.length);
  const canExpand = !isCenter && Boolean(node?.children.size);

  if (!node || (!hasText && !hasImage && !node.children.size && !isCenter)) {
    const blank = element("div", "cell empty");
    blank.setAttribute("aria-label", `${POSITION_LABELS[position]}空白`);
    return blank;
  }

  const button = element("button", "cell");
  button.type = "button";
  button.classList.toggle("center", isCenter);
  button.classList.toggle("has-image", hasImage);
  button.setAttribute("aria-pressed", String(node === selected));
  button.setAttribute("aria-label", `${POSITION_LABELS[position]} · ${label(node)}${canExpand ? " · 可展开" : ""}`);
  if (hasImage) {
    const image = element("img", "cell-image");
    image.alt = "";
    image.src = urlFor(node.images[0]);
    button.append(image);
  }
  if (!hasImage || hasText) button.append(element("span", "cell-title", label(node)));
  if (canExpand) {
    const icon = element("span", "cell-icon", "↗");
    icon.setAttribute("aria-hidden", "true");
    button.append(icon);
  }

  button.addEventListener("click", () => {
    if (canExpand) {
      openBranch(node);
    } else {
      selected = node;
      for (const other of grid.querySelectorAll("button")) {
        other.setAttribute("aria-pressed", String(other === button));
      }
      renderDetail();
      if (matchMedia("(max-width: 760px)").matches && !isCenter) {
        document.querySelector(".detail").scrollIntoView({ block: "nearest" });
      }
    }
  });
  return button;
}

function renderDetail() {
  const center = current();
  const position = selected === center ? 4 : POSITIONS.indexOf(selected.id);
  byId("position").textContent = POSITION_LABELS[position] || `格子 ${selected.id}`;
  byId("detail-title").textContent = label(selected);
  const body = selected.text.trim();
  byId("detail-text").textContent = body && body !== title(selected)
    ? body
    : (!body && !selected.images.length ? "这个格子没有文字。" : "");
  byId("detail-bottom").hidden = selected === center || !selected.children.size;

  const pictures = selected.images.map((blob) => {
    const button = element("button", "media-button");
    button.type = "button";
    button.setAttribute("aria-label", "查看原图");
    const image = element("img");
    image.alt = `${label(selected)}的图片`;
    image.src = urlFor(blob);
    button.append(image);
    button.addEventListener("click", () => {
      fullImage.src = image.src;
      dialog.showModal();
    });
    return button;
  });
  byId("media").replaceChildren(...pictures);
}

function render() {
  const center = current();
  byId("file-name").textContent = fileName;
  byId("heading").textContent = label(center);
  byId("up").hidden = stack.length === 1;
  byId("board-count").textContent = `第 ${stack.length} 层 · ${center.children.size} 个子格`;
  renderTrail();
  grid.replaceChildren(...POSITIONS.map((id, index) =>
    renderCell(id === null ? center : center.children.get(id), index)
  ));
  const extra = [...center.children.values()].filter((node) => !POSITIONS.includes(node.id));
  if (extra.length) {
    const list = element("div", "extra-cells");
    list.append(element("p", "board-hint", "其他格子"));
    for (const node of extra) {
      const button = element("button", "secondary", label(node));
      button.type = "button";
      button.addEventListener("click", () => openBranch(node));
      list.append(button);
    }
    grid.after(list);
  }
  for (const leftover of document.querySelectorAll(".extra-cells")) {
    if (leftover !== grid.nextElementSibling || !extra.length) leftover.remove();
  }
  renderDetail();
}

function message(text, isError = false) {
  status.textContent = text;
  status.hidden = !text;
  status.classList.toggle("error", isError);
}

async function load(file) {
  if (!file) return;
  const version = ++activeLoad;
  openButton.disabled = true;
  message(`正在读取 ${file.name}…`);
  try {
    const parsed = await MandalaArchive.parse(file);
    if (version !== activeLoad) return;
    if (dialog.open) dialog.close();
    for (const url of urls.values()) URL.revokeObjectURL(url);
    urls.clear();
    fileName = file.name;
    root = parsed.root;
    stack = [root];
    selected = root;
    render();
    message("");
  } catch (error) {
    if (version === activeLoad) message(`无法打开 ${file.name}。 ${error.message}`, true);
  } finally {
    if (version === activeLoad) openButton.disabled = false;
  }
}

openButton.addEventListener("click", () => input.click());
input.addEventListener("change", () => {
  load(input.files[0]);
  input.value = "";
});
byId("up").addEventListener("click", () => showLayer(stack.length - 2));
byId("expand").addEventListener("click", () => openBranch(selected));
byId("close-image").addEventListener("click", () => dialog.close());
dialog.addEventListener("close", () => fullImage.removeAttribute("src"));
dialog.addEventListener("click", (event) => {
  if (event.target === dialog) dialog.close();
});

const hasFiles = (event) => event.dataTransfer.types.includes("Files");
window.addEventListener("dragover", (event) => {
  if (!hasFiles(event)) return;
  event.preventDefault();
  overlay.hidden = false;
});
window.addEventListener("dragleave", (event) => {
  if (!event.relatedTarget) overlay.hidden = true;
});
window.addEventListener("drop", (event) => {
  if (!hasFiles(event)) return;
  event.preventDefault();
  overlay.hidden = true;
  load(event.dataTransfer.files[0]);
});

render();
