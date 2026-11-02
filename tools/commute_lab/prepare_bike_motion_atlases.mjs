import fs from 'node:fs/promises';
import path from 'node:path';
import zlib from 'node:zlib';

const stageRoot = process.argv[2] || 'assets/staging/commute-bike-v3';
const runtimeRoot = process.argv[3] || 'assets/commute/bike';
const frameSize = 320;
const columns = 4;
const rows = 4;
const frameCount = columns * rows;
const directions = [
  'north', 'north-northeast', 'northeast', 'east-northeast',
  'east', 'east-southeast', 'southeast', 'south-southeast',
  'south', 'south-southwest', 'southwest', 'west-southwest',
  'west', 'west-northwest', 'northwest', 'north-northwest',
];

const allVariants = [
  { source: 'mounted-16-source.png', output: 'mounted-16.png', original: 'mounted.png' },
  { source: 'parked-16-source.png', output: 'parked-16.png', original: 'parked.png' },
  { source: 'mounted-aero-tuck-16-source.png', output: 'mounted-aero-tuck-16.png', original: 'mounted-aero-tuck.png' },
  { source: 'mounted-acceleration-response-16-source.png', output: 'mounted-acceleration-response-16.png', original: 'mounted-acceleration-response.png' },
  { source: 'mounted-gear-shift-16-source.png', output: 'mounted-gear-shift-16.png', original: 'mounted-gear-shift.png' },
  { source: 'mounted-hard-turn-left-16-source.png', output: 'mounted-hard-turn-left-16.png', original: 'mounted-hard-turn-left.png' },
  { source: 'mounted-hard-turn-right-16-source.png', output: 'mounted-hard-turn-right-16.png', original: 'mounted-hard-turn-right.png' },
  { source: 'mounted-impact-brace-16-source.png', output: 'mounted-impact-brace-16.png', original: 'mounted-impact-brace.png' },
  { source: 'mounted-aero-tuck-transition-16-source.png', output: 'mounted-aero-tuck-transition-16.png', original: 'mounted-aero-tuck-transition.png' },
  { source: 'mounted-boost-transition-16-source.png', output: 'mounted-boost-transition-16.png', original: 'mounted-boost-transition.png' },
  { source: 'mounted-gear-shift-transition-16-source.png', output: 'mounted-gear-shift-transition-16.png', original: 'mounted-gear-shift-transition.png' },
  { source: 'mounted-turn-left-transition-16-source.png', output: 'mounted-turn-left-transition-16.png', original: 'mounted-turn-left-transition.png' },
  { source: 'mounted-turn-right-transition-16-source.png', output: 'mounted-turn-right-transition-16.png', original: 'mounted-turn-right-transition.png' },
  { source: 'mounted-impact-transition-16-source.png', output: 'mounted-impact-transition-16.png', original: 'mounted-impact-transition.png' },
];
const selectedOutputs = new Set(process.argv.slice(4));
for (const output of selectedOutputs) {
  if (!allVariants.some((variant) => variant.output === output)) throw new Error(`Unknown selected output: ${output}`);
}
const variants = selectedOutputs.size ? allVariants.filter((variant) => selectedOutputs.has(variant.output)) : allVariants;

const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n += 1) {
  let c = n;
  for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  crcTable[n] = c >>> 0;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data = Buffer.alloc(0)) {
  const typeBuffer = Buffer.from(type, 'ascii');
  const chunk = Buffer.allocUnsafe(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  typeBuffer.copy(chunk, 4);
  data.copy(chunk, 8);
  chunk.writeUInt32BE(crc32(chunk.subarray(4, 8 + data.length)), 8 + data.length);
  return chunk;
}

async function readRgbaPng(file) {
  const png = await fs.readFile(file);
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!png.subarray(0, 8).equals(signature)) throw new Error(`Not a PNG: ${file}`);
  let width; let height; let bitDepth; let colorType; let interlace;
  const idat = [];
  for (let offset = 8; offset < png.length;) {
    const length = png.readUInt32BE(offset);
    const type = png.toString('ascii', offset + 4, offset + 8);
    const data = png.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    offset += length + 12;
  }
  if (bitDepth !== 8 || colorType !== 6 || interlace !== 0) {
    throw new Error(`Expected non-interlaced 8-bit RGBA PNG at ${file}; got depth=${bitDepth}, type=${colorType}, interlace=${interlace}.`);
  }
  const stride = width * 4;
  const inflated = zlib.inflateSync(Buffer.concat(idat));
  if (inflated.length !== height * (stride + 1)) throw new Error(`Unexpected PNG data length in ${file}.`);
  const pixels = Buffer.allocUnsafe(height * stride);
  let sourceOffset = 0;
  for (let y = 0; y < height; y += 1) {
    const filter = inflated[sourceOffset++];
    const rowOffset = y * stride;
    const priorOffset = rowOffset - stride;
    for (let x = 0; x < stride; x += 1) {
      const raw = inflated[sourceOffset++];
      const left = x >= 4 ? pixels[rowOffset + x - 4] : 0;
      const up = y > 0 ? pixels[priorOffset + x] : 0;
      const upperLeft = y > 0 && x >= 4 ? pixels[priorOffset + x - 4] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = Math.floor((left + up) / 2);
      else if (filter === 4) {
        const estimate = left + up - upperLeft;
        const dl = Math.abs(estimate - left);
        const du = Math.abs(estimate - up);
        const dul = Math.abs(estimate - upperLeft);
        predictor = dl <= du && dl <= dul ? left : du <= dul ? up : upperLeft;
      } else if (filter !== 0) throw new Error(`Unsupported PNG filter ${filter} in ${file}.`);
      pixels[rowOffset + x] = (raw + predictor) & 0xff;
    }
  }
  return { width, height, pixels };
}

function makePng(width, height, pixels) {
  const stride = width * 4;
  const scanlines = Buffer.allocUnsafe(height * (stride + 1));
  for (let y = 0; y < height; y += 1) {
    const line = y * (stride + 1);
    scanlines[line] = 0;
    pixels.copy(scanlines, line + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', zlib.deflateSync(scanlines, { level: 6 })),
    pngChunk('IEND'),
  ]);
}

function alphaBounds(image, x, y, width, height) {
  let minX = width; let minY = height; let maxX = -1; let maxY = -1;
  const { pixels, width: imageWidth } = image;
  for (let py = 0; py < height; py += 1) {
    let alphaOffset = ((y + py) * imageWidth + x) * 4 + 3;
    for (let px = 0; px < width; px += 1, alphaOffset += 4) {
      if (pixels[alphaOffset] > 16) {
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
      }
    }
  }
  if (maxX < minX || maxY < minY) return null;
  return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

function labelComponents(image) {
  const pixelCount = image.width * image.height;
  const labels = new Int32Array(pixelCount);
  const queue = new Int32Array(pixelCount);
  const components = [];
  let nextId = 0;
  for (let seed = 0; seed < pixelCount; seed += 1) {
    if (labels[seed] !== 0 || image.pixels[seed * 4 + 3] <= 16) continue;
    const id = ++nextId;
    let head = 0; let tail = 0; let minX = image.width; let minY = image.height;
    let maxX = -1; let maxY = -1; let sumX = 0; let sumY = 0;
    labels[seed] = id;
    queue[tail++] = seed;
    while (head < tail) {
      const current = queue[head++];
      const x = current % image.width;
      const y = Math.floor(current / image.width);
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      sumX += x; sumY += y;
      for (let dy = -1; dy <= 1; dy += 1) {
        const ny = y + dy;
        if (ny < 0 || ny >= image.height) continue;
        for (let dx = -1; dx <= 1; dx += 1) {
          if (dx === 0 && dy === 0) continue;
          const nx = x + dx;
          if (nx < 0 || nx >= image.width) continue;
          const neighbor = ny * image.width + nx;
          if (labels[neighbor] !== 0 || image.pixels[neighbor * 4 + 3] <= 16) continue;
          labels[neighbor] = id;
          queue[tail++] = neighbor;
        }
      }
    }
    components.push({ id, area: tail, x: minX, y: minY, width: maxX - minX + 1,
      height: maxY - minY + 1, centerX: sumX / tail, centerY: sumY / tail });
  }
  return { labels, components };
}

function componentsForCell(source, labeled, index) {
  const left = Math.floor(source.width * (index % columns) / columns);
  const right = Math.floor(source.width * ((index % columns) + 1) / columns);
  const top = Math.floor(source.height * Math.floor(index / columns) / rows);
  const bottom = Math.floor(source.height * (Math.floor(index / columns) + 1) / rows);
  let group = labeled.components.filter((component) => component.area >= 24
    && component.centerX >= left && component.centerX < right
    && component.centerY >= top && component.centerY < bottom);
  if (group.length === 0) {
    const centerX = (left + right) / 2;
    const centerY = (top + bottom) / 2;
    const available = labeled.components.filter((component) => component.area >= 24);
    available.sort((a, b) => ((a.centerX - centerX) ** 2 + (a.centerY - centerY) ** 2)
      - ((b.centerX - centerX) ** 2 + (b.centerY - centerY) ** 2));
    if (available[0]) group = [available[0]];
  }
  if (group.length === 0) return null;
  const bounds = group.reduce((result, component) => ({
    x: Math.min(result.x, component.x),
    y: Math.min(result.y, component.y),
    right: Math.max(result.right, component.x + component.width),
    bottom: Math.max(result.bottom, component.y + component.height),
  }), { x: source.width, y: source.height, right: 0, bottom: 0 });
  return {
    bounds: { x: bounds.x, y: bounds.y, width: bounds.right - bounds.x, height: bounds.bottom - bounds.y },
    ids: new Set(group.map((component) => component.id)),
  };
}

function atlasBounds(image, count) {
  const bounds = [];
  for (let index = 0; index < count; index += 1) {
    const x = (index % columns) * frameSize;
    const y = Math.floor(index / columns) * frameSize;
    const frame = alphaBounds(image, x, y, frameSize, frameSize);
    if (!frame) throw new Error(`Empty reference frame ${index}.`);
    bounds.push(frame);
  }
  return bounds;
}

function expandEightBounds(eight) {
  const expanded = [];
  for (let index = 0; index < 8; index += 1) {
    const a = eight[index];
    const b = eight[(index + 1) % 8];
    expanded.push(a);
    expanded.push({
      x: Math.round((a.x + b.x) / 2),
      y: Math.round((a.y + b.y) / 2),
      width: Math.round((a.width + b.width) / 2),
      height: Math.round((a.height + b.height) / 2),
    });
  }
  return expanded;
}

function interpolatePixel(source, labels, allowedIds, x0, y0, x1, y1, tx, ty, output, out) {
  const i00 = (y0 * source.width + x0) * 4;
  const i10 = (y0 * source.width + x1) * 4;
  const i01 = (y1 * source.width + x0) * 4;
  const i11 = (y1 * source.width + x1) * 4;
  const w00 = (1 - tx) * (1 - ty);
  const w10 = tx * (1 - ty);
  const w01 = (1 - tx) * ty;
  const w11 = tx * ty;
  let alpha = 0; let red = 0; let green = 0; let blue = 0;
  let a = allowedIds.has(labels[i00 / 4]) ? source.pixels[i00 + 3] / 255 : 0;
  alpha += a * w00; red += source.pixels[i00] * a * w00; green += source.pixels[i00 + 1] * a * w00; blue += source.pixels[i00 + 2] * a * w00;
  a = allowedIds.has(labels[i10 / 4]) ? source.pixels[i10 + 3] / 255 : 0;
  alpha += a * w10; red += source.pixels[i10] * a * w10; green += source.pixels[i10 + 1] * a * w10; blue += source.pixels[i10 + 2] * a * w10;
  a = allowedIds.has(labels[i01 / 4]) ? source.pixels[i01 + 3] / 255 : 0;
  alpha += a * w01; red += source.pixels[i01] * a * w01; green += source.pixels[i01 + 1] * a * w01; blue += source.pixels[i01 + 2] * a * w01;
  a = allowedIds.has(labels[i11 / 4]) ? source.pixels[i11 + 3] / 255 : 0;
  alpha += a * w11; red += source.pixels[i11] * a * w11; green += source.pixels[i11 + 1] * a * w11; blue += source.pixels[i11 + 2] * a * w11;
  output[out] = alpha <= 0 ? 0 : Math.round(red / alpha);
  output[out + 1] = alpha <= 0 ? 0 : Math.round(green / alpha);
  output[out + 2] = alpha <= 0 ? 0 : Math.round(blue / alpha);
  output[out + 3] = alpha <= 0 ? 0 : Math.round(alpha * 255);
}

function drawScaledBounds(source, labels, allowedIds, sourceBounds, output, targetBounds, index) {
  const column = index % columns;
  const row = Math.floor(index / columns);
  const scale = Math.min(targetBounds.width / sourceBounds.width, targetBounds.height / sourceBounds.height);
  const destWidth = Math.max(1, Math.round(sourceBounds.width * scale));
  const destHeight = Math.max(1, Math.round(sourceBounds.height * scale));
  const destX = Math.round(column * frameSize + targetBounds.x + (targetBounds.width - destWidth) / 2);
  const destY = Math.round(row * frameSize + targetBounds.y + targetBounds.height - destHeight);
  const stride = columns * frameSize * 4;
  for (let dy = 0; dy < destHeight; dy += 1) {
    const sourceY = Math.max(sourceBounds.y, Math.min(sourceBounds.y + sourceBounds.height - 1,
      sourceBounds.y + (dy + 0.5) * sourceBounds.height / destHeight - 0.5));
    const y0 = Math.max(sourceBounds.y, Math.min(sourceBounds.y + sourceBounds.height - 1, Math.floor(sourceY)));
    const y1 = Math.max(sourceBounds.y, Math.min(sourceBounds.y + sourceBounds.height - 1, y0 + 1));
    const ty = Math.max(0, Math.min(1, sourceY - Math.floor(sourceY)));
    for (let dx = 0; dx < destWidth; dx += 1) {
      const sourceX = Math.max(sourceBounds.x, Math.min(sourceBounds.x + sourceBounds.width - 1,
        sourceBounds.x + (dx + 0.5) * sourceBounds.width / destWidth - 0.5));
      const x0 = Math.max(sourceBounds.x, Math.min(sourceBounds.x + sourceBounds.width - 1, Math.floor(sourceX)));
      const x1 = Math.max(sourceBounds.x, Math.min(sourceBounds.x + sourceBounds.width - 1, x0 + 1));
      const tx = Math.max(0, Math.min(1, sourceX - Math.floor(sourceX)));
      const out = (destY + dy) * stride + (destX + dx) * 4;
      interpolatePixel(source, labels, allowedIds, x0, y0, x1, y1, tx, ty, output, out);
    }
  }
}

async function prepareAtlas(variant, targetBounds) {
  const sourcePath = path.join(stageRoot, variant.source);
  const outputPath = path.join(runtimeRoot, variant.output);
  const source = await readRgbaPng(sourcePath);
  const original = await readRgbaPng(path.join(runtimeRoot, variant.original));
  const sourceAspect = source.width / source.height;
  if (source.width < 1000 || source.height < 1000 || sourceAspect < 0.88 || sourceAspect > 1.12) {
    throw new Error(`Expected a near-square 4 by 4 atlas at ${sourcePath}, got ${source.width}x${source.height}.`);
  }
  for (const [x, y] of [[0, 0], [source.width - 1, 0], [0, source.height - 1], [source.width - 1, source.height - 1]]) {
    if (source.pixels[(y * source.width + x) * 4 + 3] > 8) throw new Error(`Expected transparent source corners in ${sourcePath}.`);
  }
  if (original.width !== 1280 || original.height !== 640) {
    throw new Error(`Expected an original 1280x640 atlas at ${variant.original}.`);
  }
  const components = labelComponents(source);
  const output = Buffer.alloc(columns * rows * frameSize * frameSize * 4);
  for (let index = 0; index < frameCount; index += 1) {
    if (index % 2 === 0) {
      const oldIndex = index / 2;
      const oldX = (oldIndex % columns) * frameSize;
      const oldY = Math.floor(oldIndex / columns) * frameSize;
      const newX = (index % columns) * frameSize;
      const newY = Math.floor(index / columns) * frameSize;
      for (let row = 0; row < frameSize; row += 1) {
        const sourceOffset = (oldY + row) * original.width * 4 + oldX * 4;
        const targetOffset = (newY + row) * columns * frameSize * 4 + newX * 4;
        original.pixels.copy(output, targetOffset, sourceOffset, sourceOffset + frameSize * 4);
      }
      continue;
    }
    const selected = componentsForCell(source, components, index);
    if (!selected) throw new Error(`No separate subject found for ${directions[index]} in ${sourcePath}.`);
    drawScaledBounds(source, components.labels, selected.ids, selected.bounds,
      output, targetBounds[index], index);
  }
  await fs.writeFile(outputPath, makePng(columns * frameSize, rows * frameSize, output));
  console.log(`Wrote ${outputPath} (${directions.length} directions).`);
  return { width: columns * frameSize, height: rows * frameSize, pixels: output };
}

await fs.mkdir(runtimeRoot, { recursive: true });
const mountedOld = await readRgbaPng(path.join(runtimeRoot, 'mounted.png'));
const parkedOld = await readRgbaPng(path.join(runtimeRoot, 'parked.png'));
if (mountedOld.width !== 1280 || mountedOld.height !== 640 || parkedOld.width !== 1280 || parkedOld.height !== 640) {
  throw new Error('The existing eight-view bike atlases must remain 1280x640.');
}
const mountedTargets = expandEightBounds(atlasBounds(mountedOld, 8));
const parkedTargets = expandEightBounds(atlasBounds(parkedOld, 8));
let mounted16;
let mounted16Bounds;
const needsMountedReference = variants.some((variant) => !['mounted-16.png', 'parked-16.png'].includes(variant.output));
const preparesMountedReference = variants.some((variant) => variant.output === 'mounted-16.png');
if (needsMountedReference && !preparesMountedReference) {
  mounted16 = await readRgbaPng(path.join(runtimeRoot, 'mounted-16.png'));
  mounted16Bounds = atlasBounds(mounted16, 16);
}
for (const variant of variants) {
  let targetBounds;
  if (variant.output === 'mounted-16.png') targetBounds = mountedTargets;
  else if (variant.output === 'parked-16.png') targetBounds = parkedTargets;
  else {
    if (!mounted16) throw new Error('Mounted reference atlas must be prepared first.');
    if (!mounted16Bounds) mounted16Bounds = atlasBounds(mounted16, 16);
    targetBounds = mounted16Bounds;
  }
  const prepared = await prepareAtlas(variant, targetBounds);
  if (variant.output === 'mounted-16.png') mounted16 = prepared;
}
