#!/usr/bin/env node
// node tools/run_commute_performance_probe.cjs [--output PATH] [--baseline-source PATH]
// Optional: --seed 42, --paint blue, --profile, --captures, --capture-only, --gpu-fence, --bridge-stress, --coverage, --timeout 300
// Every invocation receives fresh workspace-local APPDATA and a private test identity.
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const options = {};
for (let index = 0; index < args.length; index += 1) {
  const flag = args[index];
  if (['--profile', '--captures', '--capture-only', '--gpu-fence', '--bridge-stress', '--coverage'].includes(flag)) options[flag] = true;
  else if (['--output', '--baseline-source', '--timeout', '--seed', '--paint'].includes(flag)) {
    if (!args[index + 1]) throw new Error('Missing value for ' + flag);
    options[flag] = args[++index];
  } else throw new Error('Unknown option: ' + flag);
}
const stamp = new Date().toISOString().replace(/[^a-z0-9]/gi, '-');
const token = stamp + '-' + Math.random().toString(16).slice(2, 10);
const output = path.resolve(options['--output'] || path.join(root, 'output', 'performance', 'motorcycle-' + token));
const appdataRoot = process.env.PICTURE_SHOP_PERFORMANCE_APPDATA_ROOT || output;
const appdata = path.join(appdataRoot, 'appdata-' + token);
fs.mkdirSync(output, { recursive: true });
fs.mkdirSync(appdata, { recursive: true });
const executable = process.env.LOVE_EXE || (process.platform === 'win32'
  ? path.join(process.env.ProgramFiles || 'C:/Program Files', 'LOVE', 'lovec.exe') : 'love');
const env = { ...process.env, APPDATA: appdata, PICTURE_SHOP_COMMUTE_RESET: '',
  PICTURE_SHOP_COMMUTE_PERFORMANCE_PROBE: '1',
  PICTURE_SHOP_BIKE_PAINT: options['--paint'] || '',
  PICTURE_SHOP_TOWN_SEED: options['--seed'] || process.env.PICTURE_SHOP_TOWN_SEED || '',
  PICTURE_SHOP_TEST_IDENTITY: process.env.PICTURE_SHOP_PERFORMANCE_TEST_IDENTITY || 'the-picture-shop-test-motorcycle-' + token,
  PICTURE_SHOP_PERFORMANCE_OUTPUT: output,
  PICTURE_SHOP_COMMUTE_BASELINE_SOURCE: options['--baseline-source'] ? path.resolve(options['--baseline-source']) : '',
  PICTURE_SHOP_PERFORMANCE_PROFILE: options['--profile'] ? '1' : '',
  PICTURE_SHOP_PERFORMANCE_GPU_FENCE: options['--gpu-fence'] ? '1' : '',
  PICTURE_SHOP_PERFORMANCE_TERRAIN_COVERAGE: options['--coverage'] ? '1' : '',
  PICTURE_SHOP_PERFORMANCE_BRIDGE_STRESS: options['--bridge-stress'] ? '1' : '',
  PICTURE_SHOP_PERFORMANCE_CAPTURES: options['--captures'] || options['--capture-only'] ? '1' : '',
  PICTURE_SHOP_PERFORMANCE_CAPTURE_ONLY: options['--capture-only'] ? '1' : '' };
const seconds = Number(options['--timeout'] || 300);
if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('Timeout must be a positive number of seconds');
const logfile = fs.createWriteStream(path.join(output, 'console.log'));
console.log('Motorcycle benchmark output: ' + output);
console.log('Close other performance tests and games for comparable results. Vsync is disabled.');
const child = spawn(executable, [root], { cwd: root, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
let timedOut = false;
const timeout = setTimeout(() => { timedOut = true; child.kill(); }, seconds * 1000);
for (const stream of [child.stdout, child.stderr]) stream.on('data', data => {
  logfile.write(data); process.stdout.write(data);
});
process.on('SIGINT', () => child.kill());
child.on('error', error => { clearTimeout(timeout); logfile.end(); console.error(error.message); process.exitCode = 1; });
child.on('close', code => {
  clearTimeout(timeout); logfile.end();
  if (timedOut) console.error('Probe exceeded ' + seconds + ' seconds and was terminated.');
  console.log('Measurements: ' + path.join(output, 'measurements.json'));
  process.exitCode = timedOut ? 124 : (code ?? 1);
});
