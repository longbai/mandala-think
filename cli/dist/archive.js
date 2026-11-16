"use strict";

const MandalaArchive = (() => {
  const CELL = String.raw`[0-9]+[.]cell(?:/Children/[0-9]+[.]cell)*`;
  const ENTRY = new RegExp(`^(${CELL})(?:/Contents/(Content[.][A-Za-z0-9]+)|/[.]DS_Store|/)$`);
  const IMAGE = { jpeg: "image/jpeg", jpg: "image/jpeg", png: "image/png", gif: "image/gif", webp: "image/webp" };
  const PREVIEW = "Representing/Representing.png";
  const LIMIT = 128 * 1024 * 1024;
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const badZip = () => new Error("ZIP 结构损坏，或此文件使用了不支持的 ZIP 格式。");

  function listEntries(buffer) {
    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);
    let end = bytes.length - 22;
    const lower = Math.max(0, end - 65535);
    while (end >= lower) {
      if (view.getUint32(end, true) === 0x06054b50 &&
          end + 22 + view.getUint16(end + 20, true) === bytes.length) break;
      end--;
    }
    if (end < lower || view.getUint32(end + 4, true) !== 0) throw badZip();
    const count = view.getUint16(end + 10, true);
    const centralSize = view.getUint32(end + 12, true);
    const centralStart = view.getUint32(end + 16, true);
    if (count === 65535 || count !== view.getUint16(end + 8, true) ||
        centralStart + centralSize > end) throw badZip();

    const entries = new Map();
    let offset = centralStart;
    for (let i = 0; i < count; i++) {
      if (offset + 46 > end || view.getUint32(offset, true) !== 0x02014b50) throw badZip();
      const nameStart = offset + 46;
      const nameEnd = nameStart + view.getUint16(offset + 28, true);
      const next = nameEnd + view.getUint16(offset + 30, true) + view.getUint16(offset + 32, true);
      if (next > centralStart + centralSize) throw badZip();
      const name = decoder.decode(bytes.subarray(nameStart, nameEnd));
      if (entries.has(name)) throw new Error("文件包含重复的 ZIP 路径。");
      entries.set(name, {
        flags: view.getUint16(offset + 8, true),
        method: view.getUint16(offset + 10, true),
        packed: view.getUint32(offset + 20, true),
        size: view.getUint32(offset + 24, true),
        local: view.getUint32(offset + 42, true),
      });
      offset = next;
    }

    return {
      entries,
      async read(name) {
        const { flags, method, packed, size, local } = entries.get(name);
        if (flags & 1) throw new Error("暂时无法读取加密的 ZIP 条目。");
        if (local + 30 > centralStart || view.getUint32(local, true) !== 0x04034b50) throw badZip();
        const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
        if (start + packed > centralStart) throw badZip();
        const input = bytes.subarray(start, start + packed);
        if (method === 0 && input.length === size) return input;
        if (method !== 8) throw badZip();

        let inflater;
        try {
          inflater = new DecompressionStream("deflate-raw");
        } catch {
          throw new Error("此浏览器不支持 ZIP 解压，请用较新版的 Safari、Chrome、Edge 或 Firefox。");
        }
        const reader = new Blob([input]).stream().pipeThrough(inflater).getReader();
        const output = new Uint8Array(size);
        let written = 0;
        try {
          while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            if (written + value.length > size) {
              await reader.cancel();
              throw badZip();
            }
            output.set(value, written);
            written += value.length;
          }
        } finally {
          reader.releaseLock();
        }
        if (written !== size) throw badZip();
        return output;
      },
    };
  }

  async function parse(file) {
    if (file.size > LIMIT) throw new Error("文件超过 128 MB。");
    const archive = listEntries(await file.arrayBuffer());
    const nodes = new Map();
    const roots = new Set();
    const makeNode = (id, path) => ({ id, path, text: "", images: [], children: new Map() });

    let expandedSize = archive.entries.get(PREVIEW)?.size ?? 0;
    const content = [];
    for (const [name, entry] of archive.entries) {
      const match = ENTRY.exec(name);
      if (!match) continue;
      const parts = match[1].split("/Children/");
      if (parts.length > 100) throw new Error("格子层级超过 100 层。");
      let parent = null;
      let path = "";
      for (const part of parts) {
        path = parent ? `${path}/Children/${part}` : part;
        const id = Number(part.slice(0, -5));
        if (!Number.isSafeInteger(id)) throw new Error("格子编号无效。");
        if (!nodes.has(path)) nodes.set(path, makeNode(id, path));
        const node = nodes.get(path);
        if (parent) {
          const existing = parent.children.get(id);
          if (existing && existing !== node) throw new Error("文件包含重复的格子编号。");
          parent.children.set(id, node);
        } else {
          roots.add(node);
        }
        parent = node;
      }
      if (!match[2]) continue;
      const type = IMAGE[match[2].split(".").pop().toLowerCase()];
      const isText = match[2] === "Content.txt";
      if (type || isText) {
        expandedSize += entry.size;
        content.push({ name, node: parent, type });
      }
    }
    if (roots.size !== 1) throw new Error("找不到唯一的 MandalArt 根格子。");
    if (expandedSize > LIMIT) throw new Error("解压后的内容超过 128 MB。");

    for (const { name, node, type } of content) {
      const data = await archive.read(name);
      if (type) node.images.push(new Blob([data], { type }));
      else node.text = decoder.decode(data);
    }
    const root = roots.values().next().value;
    if (!root.images.length && archive.entries.has(PREVIEW)) {
      root.images.push(new Blob([await archive.read(PREVIEW)], { type: "image/png" }));
    }
    return { root, count: nodes.size };
  }

  return { parse };
})();
