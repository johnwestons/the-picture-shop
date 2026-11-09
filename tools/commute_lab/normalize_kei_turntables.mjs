import fs from 'node:fs/promises';
import path from 'node:path';
import zlib from 'node:zlib';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const SOURCE = path.join(ROOT, 'assets/source/kei-delivery-truck-v1/turntables');
const RUNTIME = path.join(ROOT, 'assets/commute/truck/kei-turntables');
// Measure the visible truck, excluding faint antialiasing and baked shadows.
const ALPHA_CUTOFF = 128;
const VIEWS = {
  isometric: { cell: [314, 314], targetHeight: 144, groundAnchor: [156.5, 282], elevation: 32,
    headings: [[1,0],[2,10],[3,20],[4,30],[5,40],[6,50],[7,60],[8,70],[9,78],[11,84],
      [14,90],[18,105],[19,115],[20,125],[21,135],[22,145],[23,153],[24,160],[25,167],[26,173],[27,178],
      [33,180],[34,190],[35,200],[36,210],[37,220],[38,230],[39,240],[40,250],[41,260],
      [43,270],[50,285],[51,295],[52,305],[53,315],[54,325],[55,334],[56,342],[57,350],[58,357],[64,360]] },
  chase: { cell: [405, 243], targetHeight: 180, groundAnchor: [202, 222], elevation: 8,
    headings: [[1,0],[2,10],[3,20],[4,30],[5,40],[6,50],[7,60],[8,70],[10,80],[15,90],
      [18,105],[19,115],[20,125],[21,135],[22,145],[23,155],[24,165],[25,175],[31,178],[33,180],
      [34,190],[35,200],[36,210],[37,220],[38,230],[39,240],[40,250],[41,260],[43,270],
      [50,285],[51,295],[52,305],[53,315],[54,323],[55,331],[56,339],[57,347],[58,353],[59,358],[64,360]] },
};

function crc32(buffer) {
  let value = 0xffffffff;
  for (const byte of buffer) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1;
  }
  return (value ^ 0xffffffff) >>> 0;
}

function pngChunk(name, data) {
  const type = Buffer.from(name);
  const output = Buffer.alloc(data.length + 12);
  output.writeUInt32BE(data.length, 0);
  type.copy(output, 4);
  data.copy(output, 8);
  output.writeUInt32BE(crc32(Buffer.concat([type, data])), data.length + 8);
  return output;
}

function encodePng(width, height, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);header.writeUInt32BE(height, 4);
  header[8] = 8;header[9] = 6;
  const rows = Buffer.alloc(height * (width * 4 + 1));
  const stride = width * 4;
  const paeth = (a, b, c) => {
    const p = a + b - c, da = Math.abs(p - a), db = Math.abs(p - b), dc = Math.abs(p - c);
    return da <= db && da <= dc ? a : db <= dc ? b : c;
  };
  for (let y = 0; y < height; y++) {
    const source = y * stride, destination = y * (stride + 1);
    let bestFilter = 0, bestScore = Infinity, bestRow;
    for (let filter = 0; filter <= 4; filter++) {
      const candidate = Buffer.allocUnsafe(stride);
      let score = 0;
      for (let x = 0; x < stride; x++) {
        const raw = pixels[source + x], left = x >= 4 ? pixels[source + x - 4] : 0;
        const up = y ? pixels[source + x - stride] : 0;
        const upperLeft = y && x >= 4 ? pixels[source + x - stride - 4] : 0;
        const predictor = filter === 1 ? left : filter === 2 ? up
          : filter === 3 ? Math.floor((left + up) / 2)
            : filter === 4 ? paeth(left, up, upperLeft) : 0;
        const encoded = (raw - predictor) & 255;
        candidate[x] = encoded;
        score += Math.abs(encoded < 128 ? encoded : encoded - 256);
      }
      if (score < bestScore) { bestScore = score;bestFilter = filter;bestRow = candidate; }
    }
    rows[destination] = bestFilter;
    bestRow.copy(rows, destination + 1);
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', header),
    pngChunk('IDAT', zlib.deflateSync(rows, { level: 9 })),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

function decodePng(bytes, filename) {
  const chunks = [];
  let width, height, bitDepth, colorType, interlace;
  for (let offset = 8; offset < bytes.length;) {
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);height = data.readUInt32BE(4);
      bitDepth = data[8];colorType = data[9];interlace = data[12];
    } else if (type === 'IDAT') chunks.push(data);
    offset += length + 12;
  }
  if (bitDepth !== 8 || colorType !== 6 || interlace !== 0)
    throw new Error(`${filename} must be a non-interlaced RGBA8 PNG.`);
  const packed = zlib.inflateSync(Buffer.concat(chunks));
  const stride = width * 4, pixels = Buffer.alloc(height * stride);
  const paeth = (a, b, c) => {
    const p = a + b - c, da = Math.abs(p - a), db = Math.abs(p - b), dc = Math.abs(p - c);
    return da <= db && da <= dc ? a : db <= dc ? b : c;
  };
  for (let y = 0; y < height; y++) {
    const row = y * (stride + 1), filter = packed[row], target = y * stride;
    for (let x = 0; x < stride; x++) {
      const raw = packed[row + 1 + x], left = x >= 4 ? pixels[target + x - 4] : 0;
      const up = y ? pixels[target + x - stride] : 0;
      const upperLeft = y && x >= 4 ? pixels[target + x - stride - 4] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = Math.floor((left + up) / 2);
      else if (filter === 4) predictor = paeth(left, up, upperLeft);
      else if (filter !== 0) throw new Error(`${filename} contains unsupported PNG filter ${filter}.`);
      pixels[target + x] = (raw + predictor) & 255;
    }
  }
  return { width, height, pixels };
}

function cellRect(image, index) {
  const column = index % 4, row = Math.floor(index / 4);
  const left = Math.floor(column * image.width / 4), right = Math.floor((column + 1) * image.width / 4);
  const top = Math.floor(row * image.height / 4), bottom = Math.floor((row + 1) * image.height / 4);
  return { left, top, width: right - left, height: bottom - top };
}

function measure(image, rect) {
  let minX = rect.width, minY = rect.height, maxX = -1, maxY = -1;
  let weight = 0, weightedX = 0, weightedY = 0;
  for (let y = 0; y < rect.height; y++) for (let x = 0; x < rect.width; x++) {
    const alpha = image.pixels[((rect.top + y) * image.width + rect.left + x) * 4 + 3];
    if (alpha <= ALPHA_CUTOFF) continue;
    minX = Math.min(minX, x);maxX = Math.max(maxX, x);
    minY = Math.min(minY, y);maxY = Math.max(maxY, y);
    weight += alpha;weightedX += x * alpha;weightedY += y * alpha;
  }
  if (maxX < 0) throw new Error(`Frame cell at ${rect.left},${rect.top} is empty.`);
  return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1,
    centerX: weightedX / weight, centerY: weightedY / weight };
}

function headingForFrame(frame, anchors) {
  let previous = anchors[0], next = anchors[anchors.length - 1];
  for (let index = 1; index < anchors.length; index++) {
    if (frame <= anchors[index][0]) { previous = anchors[index - 1]; next = anchors[index]; break; }
  }
  const progress = (frame - previous[0]) / (next[0] - previous[0]);
  return previous[1] + (next[1] - previous[1]) * progress;
}

function samplePremultiplied(image, rect, x, y) {
  if (x < 0 || y < 0 || x > rect.width - 1 || y > rect.height - 1) return [0, 0, 0, 0];
  const x0 = Math.floor(x), y0 = Math.floor(y), x1 = Math.min(rect.width - 1, x0 + 1), y1 = Math.min(rect.height - 1, y0 + 1);
  const tx = x - x0, ty = y - y0;
  const taps = [
    [x0,y0,(1 - tx) * (1 - ty)], [x1,y0,tx * (1 - ty)],
    [x0,y1,(1 - tx) * ty], [x1,y1,tx * ty],
  ];
  let alpha = 0, red = 0, green = 0, blue = 0;
  for (const [sx, sy, factor] of taps) {
    const offset = ((rect.top + sy) * image.width + rect.left + sx) * 4;
    const a = image.pixels[offset + 3] / 255 * factor;
    alpha += a;red += image.pixels[offset] * a;green += image.pixels[offset + 1] * a;blue += image.pixels[offset + 2] * a;
  }
  if (alpha <= 1e-8) return [0, 0, 0, 0];
  return [Math.round(red / alpha), Math.round(green / alpha), Math.round(blue / alpha), Math.round(alpha * 255)];
}

function drawNormalizedCell(sourceImage, rect, bounds, scale, cellWidth, cellHeight, targetCenter) {
  const output = Buffer.alloc(cellWidth * cellHeight * 4);
  for (let y = 0; y < cellHeight; y++) for (let x = 0; x < cellWidth; x++) {
    const sx = (bounds.x + (bounds.width - 1) / 2) + (x - targetCenter[0]) / scale;
    const sy = (bounds.y + bounds.height - 1) + (y - targetCenter[1]) / scale;
    const color = samplePremultiplied(sourceImage, rect, sx, sy);
    const offset = (y * cellWidth + x) * 4;
    output[offset] = color[0];output[offset + 1] = color[1];
    output[offset + 2] = color[2];output[offset + 3] = color[3];
  }
  return output;
}

function pasteCell(destination, pageWidth, cell, cellWidth, cellHeight, index) {
  const left = index % 4 * cellWidth, top = Math.floor(index / 4) * cellHeight;
  for (let y = 0; y < cellHeight; y++) {
    const from = y * cellWidth * 4, to = ((top + y) * pageWidth + left) * 4;
    cell.copy(destination, to, from, from + cellWidth * 4);
  }
}

function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }

async function normalizeView(kind, view) {
  const pages = [], hashes = [];
  for (let page = 1; page <= 4; page++) {
    const filename = `${kind}-64-${page}.png`;
    const bytes = await fs.readFile(path.join(SOURCE, filename));
    hashes.push({ file: filename, sha256: hash(bytes) });
    pages.push(decodePng(bytes, filename));
  }
  const frames = [];
  for (let index = 0; index < 64; index++) {
    const page = pages[Math.floor(index / 16)], rect = cellRect(page, index % 16);
    frames.push({ page, rect, source: measure(page, rect) });
  }
  // These are independently painted perspective views, not renders of a
  // shared orthographic cuboid. Fitting their bounding AREA to a rotated
  // cuboid imposed a four-times-per-turn size pulse. Use the same visible
  // roof-to-tire span and tire baseline at every heading instead. Scale both
  // axes together so the artist's proportions and changing width survive.
  const [cellWidth, cellHeight] = view.cell;
  const outputPageWidth = cellWidth * 4, outputPageHeight = cellHeight * 4;
  const pagePixels = Array.from({ length: 4 }, () => Buffer.alloc(outputPageWidth * outputPageHeight * 4));
  const auditFrames = [];

  for (let index = 0; index < 64; index++) {
    const frame = frames[index];
    let scale = (view.targetHeight - 1) / (frame.source.height - 1);
    const destinationAnchor = [...view.groundAnchor];
    let normalizedCell, normalizedBounds;
    // Resampling a curved tire or roof can move the alpha threshold by a
    // pixel. Register the rasterized result, not only the floating-point box.
    for (let pass = 0; pass < 6; pass++) {
      normalizedCell = drawNormalizedCell(frame.page, frame.rect, frame.source, scale,
        cellWidth, cellHeight, destinationAnchor);
      normalizedBounds = measure({ width: cellWidth, height: cellHeight, pixels: normalizedCell },
        { left: 0, top: 0, width: cellWidth, height: cellHeight });
      const baselineError = normalizedBounds.y + normalizedBounds.height - 1 - view.groundAnchor[1];
      if (normalizedBounds.height === view.targetHeight && baselineError === 0) break;
      if (pass < 5) {
        scale *= view.targetHeight / normalizedBounds.height;
        destinationAnchor[1] -= baselineError;
      }
    }
    const normalizedPage = pagePixels[Math.floor(index / 16)];
    pasteCell(normalizedPage, outputPageWidth, normalizedCell, cellWidth, cellHeight, index % 16);
    auditFrames.push({ frame: index + 1,
      headingDegrees: round(headingForFrame(index + 1, view.headings)),
      sourceBounds: { x: frame.source.x, y: frame.source.y, width: frame.source.width, height: frame.source.height },
      scale: round(scale),
      runtimeBounds: { x: normalizedBounds.x, y: normalizedBounds.y,
        width: normalizedBounds.width, height: normalizedBounds.height },
      runtimeGroundAnchor: [normalizedBounds.x + (normalizedBounds.width - 1) / 2,
        normalizedBounds.y + normalizedBounds.height - 1] });
  }

  const outputs = [];
  await fs.mkdir(RUNTIME, { recursive: true });
  for (let page = 1; page <= 4; page++) {
    const filename = `${kind}-64-${page}.png`;
    const bytes = encodePng(outputPageWidth, outputPageHeight, pagePixels[page - 1]);
    await fs.writeFile(path.join(RUNTIME, filename), bytes);
    outputs.push({ file: filename, dimensions: [outputPageWidth, outputPageHeight], sha256: hash(bytes) });
  }
  return { kind, cell: view.cell, targetHeight: view.targetHeight,
    groundAnchor: view.groundAnchor, selectedFrames: view.headings.filter(([f]) => f !== 64).map(([f]) => f),
    sourcePages: hashes, runtimePages: outputs, frames: auditFrames };
}

function round(value) { return Math.round(value * 1000) / 1000; }

async function main() {
  const views = [];
  for (const [kind, view] of Object.entries(VIEWS)) views.push(await normalizeView(kind, view));
  const continuity = views.map(view => {
    const heights = view.frames.map(frame => frame.runtimeBounds.height);
    // Follow the actual runtime selector, including the last-to-first seam.
    const selected = view.selectedFrames.map(frame => view.frames[frame - 1]);
    const maxSelectedHeightStep = Math.max(...selected.map((frame, i) =>
      Math.abs(frame.runtimeBounds.height - selected[(i + 1) % selected.length].runtimeBounds.height)));
    const maxHeightError = Math.max(...heights.map(height => Math.abs(height - view.targetHeight)));
    const maxGroundAnchorError = Math.max(...view.frames.flatMap(frame =>
      frame.runtimeGroundAnchor.map((v, axis) => Math.abs(v - view.groundAnchor[axis]))));
    if (maxHeightError > 2 || maxGroundAnchorError > 1 || maxSelectedHeightStep > 2)
      throw new Error(`${view.kind}: roof/tire registration exceeded tolerance`);
    return { kind: view.kind, frameCount: 64, selectedFrameCount: selected.length,
      minHeight: Math.min(...heights), maxHeight: Math.max(...heights),
      maxHeightError, maxGroundAnchorError, maxSelectedHeightStep, includesWrapSeam: true };
  });
  const audit = { version: 2, sourceDirectory: 'assets/source/kei-delivery-truck-v1/turntables',
    runtimeDirectory: 'assets/commute/truck/kei-turntables', alphaCutoff: ALPHA_CUTOFF,
    method: 'Uniform per-frame scale to a fixed visible roof-to-tire height; horizontal bounds center and tire baseline registered to a common ground anchor. No heading-dependent area or scale correction.',
    views, validation: { allFrameCellsMeasured: true, uniformRuntimeGrid: true, continuity } };
  await fs.writeFile(path.join(SOURCE, 'normalization-audit.json'), `${JSON.stringify(audit, null, 2)}\n`);
  const manifestPath = path.join(SOURCE, 'manifest.json');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  manifest.normalization.method = audit.method;
  manifest.normalization.alphaCutoff = ALPHA_CUTOFF;
  manifest.normalization.roofToTirePixels = Object.fromEntries(views.map(v => [v.kind, v.targetHeight]));
  manifest.validation = { viewCountsMatch: true, eachViewContainsFourPagesOfSixteenFrames: true,
    runtimeReady: true, allRuntimePagesHaveUniformGridCells: true, continuity };
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(JSON.stringify(continuity, null, 2));
}

await main();
