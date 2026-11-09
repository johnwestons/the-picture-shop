// Node-only importer acceptance. Synthetic color cells are test fixtures, never
// production review manifests or motorcycle artwork.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import zlib from 'node:zlib';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { allVariants, directions, main, validateReviewManifest } from './prepare_bike_motion_atlases.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const reportRoot = path.join(root, 'output/bike-direction-audit');
await fs.mkdir(reportRoot, { recursive: true });
const folder = await fs.mkdtemp(path.join(reportRoot, 'importer-test-'));
const stage = path.join(folder, 'stage');const runtime = path.join(folder, 'runtime');
await fs.mkdir(stage);await fs.mkdir(runtime);
const checks = [];
function check(name, action) { action();checks.push(name); }
async function asyncCheck(name, action) { await action();checks.push(name); }
function crc(buffer) {
  let value = 0xffffffff;
  for (const byte of buffer) {
    value ^= byte;
    for (let n = 0; n < 8; n++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1;
  }
  return (value ^ 0xffffffff) >>> 0;
}
function chunk(name, data) {
  const type = Buffer.from(name);const result = Buffer.alloc(data.length + 12);
  result.writeUInt32BE(data.length);type.copy(result, 4);data.copy(result, 8);
  result.writeUInt32BE(crc(Buffer.concat([type, data])), data.length + 8);return result;
}
function png(width, height, pixels) {
  const header = Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height, 4);header[8] = 8;header[9] = 6;
  const rows = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) pixels.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}
function fixture(count, empty = -1, boundsForCell) {
  const cell = count === 16 ? 256 : 320, width = cell * 4, height = cell * count / 4;
  const pixels = Buffer.alloc(width * height * 4);
  for (let i = 0; i < count; i++) {
    if (i === empty) continue;
    const x0 = i % 4 * cell, y0 = Math.floor(i / 4) * cell;
    const b = boundsForCell ? boundsForCell(i) : { x: 100, y: 130, width: 110, height: 110 };
    for (let y = b.y; y < b.y + b.height; y++) for (let x = b.x; x < b.x + b.width; x++) {
      const offset = ((y0 + y) * width + x0 + x) * 4;
      pixels[offset] = 20 + i * 10;pixels[offset + 1] = 40;pixels[offset + 2] = 80;pixels[offset + 3] = 255;
    }
  }
  return { width, height, pixels, bytes: png(width, height, pixels) };
}
function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }
const source = fixture(16), original = fixture(8);
const variants = allVariants.slice(0, 2);
for (const v of variants) {
  await fs.writeFile(path.join(stage, v.source), source.bytes);
  await fs.writeFile(path.join(runtime, v.original), original.bytes);
}
await fs.writeFile(path.join(folder, 'synthetic-review.txt'), 'Synthetic cell markers for importer test only. No motorcycle art approved.\n');
function approved() {
  return { version: 1, status: 'approved_direction_review',
    review: { reviewer: 'Synthetic test fixture', evidence: 'synthetic-review.txt' },
    atlases: Object.fromEntries(variants.map(v => [v.output, {
      sourceSha256: hash(source.bytes), originalSha256: hash(original.bytes),
      frames: directions.map((direction, index) => ({ direction, observedDirection: direction, reviewed: true,
        source: index % 2 === 0 ? 'original' : 'generated', cell: index % 2 === 0 ? index / 2 + 1 : 17 - index }))
    }])) };
}
const clone = value => structuredClone(value);
const good = approved();const first = variants[0].output;
function rejects(change) { const manifest = clone(good);change(manifest);assert.throws(() => validateReviewManifest(manifest, variants)); }
check('reviewed_map_accepts_explicit_nonordinal_source_cells', () => {
  const plan = validateReviewManifest(good, variants).get(first);assert.equal(plan.frames[1].cell, 16);
});
check('missing_review_status_rejected', () => rejects(m => { delete m.status; }));
check('missing_visual_reviewer_rejected', () => rejects(m => { m.review.reviewer = ''; }));
check('missing_review_evidence_rejected', () => rejects(m => { delete m.review.evidence; }));
check('framecount_without_direction_review_rejected', () => rejects(m => { delete m.atlases[first].frames[1].observedDirection; }));
check('observed_wrong_facing_rejected', () => rejects(m => { m.atlases[first].frames[1].observedDirection = 'east'; }));
check('unreviewed_frame_rejected', () => rejects(m => { m.atlases[first].frames[1].reviewed = false; }));
check('duplicate_destination_direction_rejected', () => rejects(m => { m.atlases[first].frames[1].direction = 'north'; }));
check('duplicate_generated_subject_rejected', () => rejects(m => { m.atlases[first].frames[3].cell = 16; }));
check('original_compass_views_cannot_be_remapped', () => rejects(m => { m.atlases[first].frames[0].cell = 2; }));
check('missing_source_hash_rejected', () => rejects(m => { delete m.atlases[first].sourceSha256; }));
check('out_of_bounds_cell_rejected', () => rejects(m => { m.atlases[first].frames[1].cell = 17; }));
const reviewPath = path.join(folder, 'review.json');
async function writeReview(manifest) { await fs.writeFile(reviewPath, JSON.stringify(manifest)); }
async function noOutputs() {
  for (const v of variants) await assert.rejects(fs.access(path.join(runtime, v.output)), { code: 'ENOENT' });
}
const args = [stage, runtime, '--review-manifest', reviewPath, ...variants.map(v => v.output)];
await asyncCheck('old_invocation_fails_before_output', async () => { await assert.rejects(main([stage, runtime]), /review-manifest/);await noOutputs(); });
await asyncCheck('later_source_hash_mismatch_prevents_all_writes', async () => {
  const bad = clone(good);bad.atlases[variants[1].output].sourceSha256 = '0'.repeat(64);
  await writeReview(bad);await assert.rejects(main(args), /Reviewed source has changed/);await noOutputs();
});
await asyncCheck('changed_original_reference_prevents_all_writes', async () => {
  const bad = clone(good);bad.atlases[first].originalSha256 = '0'.repeat(64);
  await writeReview(bad);await assert.rejects(main(args), /Reviewed source has changed/);await noOutputs();
});
await asyncCheck('missing_review_artifact_prevents_all_writes', async () => {
  const bad = clone(good);bad.review.evidence = 'missing.png';await writeReview(bad);
  await assert.rejects(main(args), { code: 'ENOENT' });await noOutputs();
});
await asyncCheck('empty_reviewed_cell_never_substitutes_neighbor_or_partially_writes', async () => {
  const empty = fixture(16, 15), bad = clone(good), v = variants[1];
  await fs.writeFile(path.join(stage, v.source), empty.bytes);bad.atlases[v.output].sourceSha256 = hash(empty.bytes);
  await writeReview(bad);await assert.rejects(main(args), /No separate subject found/);await noOutputs();
  await fs.writeFile(path.join(stage, v.source), source.bytes);
});
await writeReview(good);await main(args);
function decode(bytes) {
  const blocks = [];let width, height;
  for (let i = 8; i < bytes.length;) {
    const length = bytes.readUInt32BE(i), type = bytes.toString('ascii', i + 4, i + 8), data = bytes.subarray(i + 8, i + 8 + length);
    if (type === 'IHDR') { width = data.readUInt32BE(0);height = data.readUInt32BE(4); }
    if (type === 'IDAT') blocks.push(data);i += length + 12;
  }
  const rows = zlib.inflateSync(Buffer.concat(blocks)), pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) { assert.equal(rows[y * (width * 4 + 1)], 0);rows.copy(pixels, y * width * 4, y * (width * 4 + 1) + 1, (y + 1) * (width * 4 + 1)); }
  return { width, height, pixels };
}
const output = decode(await fs.readFile(path.join(runtime, first)));
check('reviewed_generated_mapping_controls_actual_pixels', () => {
  const offset = (185 * output.width + 320 + 155) * 4;
  assert.equal(output.pixels[offset], 170); // source cell16, not implicit cell2 (30)
});
check('original_eight_frames_remain_byte_exact', () => {
  for (let old = 0; old < 8; old++) for (let y = 0; y < 320; y++) {
    const a = ((Math.floor(old / 4) * 320 + y) * original.width + old % 4 * 320) * 4;
    const b = ((Math.floor(old * 2 / 4) * 320 + y) * output.width + old * 2 % 4 * 320) * 4;
    assert.deepEqual(output.pixels.subarray(b, b + 1280), original.pixels.subarray(a, a + 1280));
  }
});
// A cropped tuck pose has smaller, angle-dependent bounds than mounted.
// Its new intermediate views must fit between its own adjacent originals.
const action = allVariants.find(v => v.output === 'mounted-aero-tuck-16.png');
const poseBounds = index => {
  const size = 64 + index * 4;
  return { x: 160 - size / 2, y: 240 - size, width: size, height: size };
};
const actionOriginal = fixture(8, -1, poseBounds);
await fs.writeFile(path.join(stage, action.source), source.bytes);
await fs.writeFile(path.join(runtime, action.original), actionOriginal.bytes);
const actionReview = clone(good);
actionReview.atlases = { [action.output]: { ...clone(good.atlases[first]), originalSha256: hash(actionOriginal.bytes) } };
await writeReview(actionReview);
await main([stage, runtime, '--review-manifest', reviewPath, action.output]);
const actionOutput = decode(await fs.readFile(path.join(runtime, action.output)));
function cellBounds(image, index) {
  const ox = index % 4 * 320, oy = Math.floor(index / 4) * 320;
  let minX = 320, minY = 320, maxX = -1, maxY = -1;
  for (let y = 0; y < 320; y++) for (let x = 0; x < 320; x++) {
    if (image.pixels[((oy + y) * image.width + ox + x) * 4 + 3] > 16) {
      minX = Math.min(minX, x);minY = Math.min(minY, y);maxX = Math.max(maxX, x);maxY = Math.max(maxY, y);
    }
  }
  return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}
check('action_intermediate_bounds_follow_its_adjacent_original_poses', () => {
  for (let originalCell = 0; originalCell < 8; originalCell++) {
    const a = poseBounds(originalCell), b = poseBounds((originalCell + 1) % 8);
    const expected = Object.fromEntries(['x', 'y', 'width', 'height'].map(key => [key, Math.round((a[key] + b[key]) / 2)]));
    assert.deepEqual(cellBounds(actionOutput, originalCell * 2 + 1), expected);
  }
});
check('action_original_eight_frames_still_remain_byte_exact', () => {
  for (let old = 0; old < 8; old++) for (let y = 0; y < 320; y++) {
    const a = ((Math.floor(old / 4) * 320 + y) * actionOriginal.width + old % 4 * 320) * 4;
    const b = ((Math.floor(old * 2 / 4) * 320 + y) * actionOutput.width + old * 2 % 4 * 320) * 4;
    assert.deepEqual(actionOutput.pixels.subarray(b, b + 1280), actionOriginal.pixels.subarray(a, a + 1280));
  }
});
await asyncCheck('action_import_needs_only_its_own_reviewed_original_reference', async () => {
  const isolated = path.join(folder, 'action-only');await fs.mkdir(isolated);
  await fs.writeFile(path.join(isolated, action.original), actionOriginal.bytes);
  await main([stage, isolated, '--review-manifest', reviewPath, action.output]);
  assert.deepEqual(await fs.readFile(path.join(isolated, action.output)), await fs.readFile(path.join(runtime, action.output)));
});
// Angular width changes must not shrink the rider's height. A broad generated
// view can extend beyond its narrower neighbors while remaining inside its cell.
const wideSource = fixture(16, -1, () => ({ x: 28, y: 100, width: 200, height: 100 }));
await fs.writeFile(path.join(stage, action.source), wideSource.bytes);
actionReview.atlases[action.output].sourceSha256 = hash(wideSource.bytes);
await writeReview(actionReview);await main([stage, runtime, '--review-manifest', reviewPath, action.output]);
const wideOutput = decode(await fs.readFile(path.join(runtime, action.output)));
check('wider_intermediate_keeps_adjacent_pose_height_and_source_aspect', () => {
  for (let originalCell = 0; originalCell < 8; originalCell++) {
    const expectedHeight = (poseBounds(originalCell).height + poseBounds((originalCell + 1) % 8).height) / 2;
    const b = cellBounds(wideOutput, originalCell * 2 + 1);
    assert.deepEqual(b, { x: 160 - expectedHeight, y: 240 - expectedHeight,
      width: expectedHeight * 2, height: expectedHeight });
  }
});
const veryWideSource = fixture(16, -1, () => ({ x: 8, y: 120, width: 240, height: 40 }));
await fs.writeFile(path.join(stage, action.source), veryWideSource.bytes);
actionReview.atlases[action.output].sourceSha256 = hash(veryWideSource.bytes);
await writeReview(actionReview);await main([stage, runtime, '--review-manifest', reviewPath, action.output]);
const cappedOutput = decode(await fs.readFile(path.join(runtime, action.output)));
check('extreme_width_caps_uniformly_at_safe_cell_margin_and_keeps_baseline', () => {
  for (let originalCell = 0; originalCell < 8; originalCell++) {
    const b = cellBounds(cappedOutput, originalCell * 2 + 1);
    assert.equal(b.width, 304);assert.equal(b.height, Math.round(304 / 6));
    assert.equal(b.x, 8);assert.equal(b.y + b.height, 240);
    assert.equal(b.x + b.width / 2, 160);
  }
});
const report = { checks, passed: checks.length, fixtureDirectory: folder };
await fs.writeFile(path.join(root, 'output/bike-direction-audit/importer-tests.json'), JSON.stringify(report, null, 2) + '\n');
console.log('PASS ' + checks.length + ' importer checks');
