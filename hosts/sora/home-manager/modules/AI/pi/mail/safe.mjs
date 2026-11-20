import { statfs } from 'node:fs/promises';
import { totalmem, uptime, loadavg, cpus } from 'node:os';
import { bounded, canonical, closed, text } from './core.mjs';

// No URL, path, shell, environment, or private-file inputs. Overrides are trusted in-process test dependencies only.
export const SAFE_NAMES = Object.freeze(['weather', 'machine_status']);
export function safePlan(value) {
  closed(value, ['kind', 'operations']);
  if (value.kind !== 'safe' || !Array.isArray(value.operations) || value.operations.length < 1 || value.operations.length > 2) throw new Error('invalid_safe_plan');
  const names = new Set();
  for (const op of value.operations) {
    closed(op, ['name', 'args']);
    if (!SAFE_NAMES.includes(op.name) || names.has(op.name)) throw new Error('invalid_safe_operation');
    names.add(op.name);
    if (op.name === 'machine_status') closed(op.args, []);
    else {
      closed(op.args, ['city', 'country']);
      text(op.args.city, 100, 1);
      if (!/^[\p{L}\p{M} .'-]+$/u.test(op.args.city) || op.args.city.trim() !== op.args.city || !/^[A-Z]{2}$/.test(op.args.country)) throw new Error('invalid_weather_location');
    }
  }
  return value;
}
function number(value, min, max) {
  if (!Number.isFinite(value) || value < min || value > max) throw new Error('invalid_safe_number');
  return value;
}
function stamp(value) {
  text(value, 30, 1);
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d{3})?Z)?$/.test(value)) throw new Error('invalid_safe_time');
  // Open-Meteo's minute-only timestamps have no suffix, but the result timezone is explicitly UTC.
  const iso = value.endsWith('Z') ? (value.includes('.') ? value : value.replace('Z', '.000Z')) : value + ':00.000Z';
  const time = Date.parse(iso);
  if (!Number.isFinite(time) || new Date(time).toISOString() !== iso) throw new Error('invalid_safe_time');
  return time;
}
export function safeResult(op, value) {
  if (Buffer.byteLength(canonical(value)) > 4096) throw new Error('safe_result_too_large');
  if (op.name === 'weather') {
    closed(value, ['source', 'timezone', 'utcOffsetSeconds', 'fetchedAt', 'city', 'country', 'observedAt', 'temperatureC', 'apparentTemperatureC', 'humidityPercent', 'precipitationMm', 'weatherCode', 'windKmh']);
    if (value.source !== 'Open-Meteo model estimate' || value.timezone !== 'UTC' || value.utcOffsetSeconds !== 0 || value.country !== op.args.country) throw new Error('invalid_weather_result');
    text(value.city, 100, 1); stamp(value.observedAt); stamp(value.fetchedAt);
    number(value.temperatureC, -100, 70); number(value.apparentTemperatureC, -120, 100);
    number(value.humidityPercent, 0, 100); number(value.precipitationMm, 0, 1000);
    number(value.weatherCode, 0, 99); number(value.windKmh, 0, 500);
  } else if (op.name === 'machine_status') {
    closed(value, ['machine', 'collectedAt', 'uptimeSeconds', 'logicalCpus', 'loadAverage', 'ramAvailableBytes', 'ramTotalBytes', 'diskAvailableBytes', 'diskTotalBytes']);
    if (value.machine !== 'Sora') throw new Error('invalid_machine_result');
    stamp(value.collectedAt); number(value.uptimeSeconds, 0, 1e10); number(value.logicalCpus, 1, 65536);
    if (!Number.isInteger(value.logicalCpus) || !Array.isArray(value.loadAverage) || value.loadAverage.length !== 3) throw new Error('invalid_machine_result');
    value.loadAverage.forEach(n => number(n, 0, 1e9));
    number(value.ramTotalBytes, 1, Number.MAX_SAFE_INTEGER); number(value.ramAvailableBytes, 0, value.ramTotalBytes);
    number(value.diskTotalBytes, 1, Number.MAX_SAFE_INTEGER); number(value.diskAvailableBytes, 0, value.diskTotalBytes);
  } else throw new Error('invalid_safe_operation');
  return value;
}
// Historical snapshots may be replayed as data; only automatic dispatch requires freshness.
export function safeFresh(op, value, now = Date.now()) {
  safeResult(op, value);
  const fresh = (value, maxAge) => {
    const age = now - stamp(value);
    return Number.isFinite(now) && age >= -120000 && age <= maxAge;
  };
  return op.name === 'weather'
    ? fresh(value.fetchedAt, 300000) && fresh(value.observedAt, 5400000)
    : fresh(value.collectedAt, 300000);
}
async function json(url, fetchImpl, signal) {
  // URLs are constructed only below. Redirects, including same-host redirects, are forbidden.
  const timeout = AbortSignal.timeout(5000);
  const stop = signal ? AbortSignal.any([signal, timeout]) : timeout;
  const res = await bounded(fetchImpl(url, { redirect: 'error', signal: stop }), stop);
  if (!res.ok || res.redirected || !res.headers.get('content-type')?.startsWith('application/json')) throw new Error('weather_http_failed');
  const reader = res.body.getReader(); const chunks = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await bounded(reader.read(), stop);
      if (done) break;
      size += value.length;
      if (size > 32768) throw new Error('weather_response_limit');
      chunks.push(value);
    }
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
  } finally { void reader.cancel().catch(() => {}); }
}
export async function executeSafe(op, signal, dependencies = {}) {
  safePlan({ kind: 'safe', operations: [op] });
  signal?.throwIfAborted();
  let result;
  if (op.name === 'weather') {
    const fetchImpl = dependencies.fetchImpl ?? fetch;
    const geo = new URL('https://geocoding-api.open-meteo.com/v1/search');
    geo.search = new URLSearchParams({ name: op.args.city, countryCode: op.args.country, count: '1', language: 'en', format: 'json' }).toString();
    const locations = await json(geo, fetchImpl, signal);
    if (!Array.isArray(locations.results) || locations.results.length !== 1) throw new Error('weather_location_not_found');
    const place = locations.results[0];
    text(place.name, 100, 1);
    if (place.country_code !== op.args.country) throw new Error('weather_country_mismatch');
    number(place.latitude, -90, 90); number(place.longitude, -180, 180);
    const forecast = new URL('https://api.open-meteo.com/v1/forecast');
    forecast.search = new URLSearchParams({ latitude: String(place.latitude), longitude: String(place.longitude), current: 'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m', temperature_unit: 'celsius', wind_speed_unit: 'kmh', precipitation_unit: 'mm', timezone: 'UTC', forecast_days: '1' }).toString();
    const data = await json(forecast, fetchImpl, signal);
    const c = data.current;
    if (!c || typeof c !== 'object' || !['GMT', 'UTC'].includes(data.timezone) || data.utc_offset_seconds !== 0) throw new Error('weather_current_missing');
    result = { source: 'Open-Meteo model estimate', timezone: 'UTC', utcOffsetSeconds: 0, fetchedAt: new Date().toISOString(), city: place.name, country: place.country_code, observedAt: c.time, temperatureC: c.temperature_2m, apparentTemperatureC: c.apparent_temperature, humidityPercent: c.relative_humidity_2m, precipitationMm: c.precipitation, weatherCode: c.weather_code, windKmh: c.wind_speed_10m };
  } else {
    const os = dependencies.os ?? { availableMemory: () => process.availableMemory(), totalmem, uptime, loadavg, cpus };
    const disk = dependencies.statfsImpl ?? statfs;
    let fs;
    try { fs = await bounded(disk('/persist'), signal); }
    catch (error) { if (error.code !== 'ENOENT') throw error; fs = await bounded(disk('/'), signal); }
    result = { machine: 'Sora', collectedAt: new Date().toISOString(), uptimeSeconds: os.uptime(), logicalCpus: os.cpus().length, loadAverage: os.loadavg(), ramAvailableBytes: os.availableMemory(), ramTotalBytes: os.totalmem(), diskAvailableBytes: fs.bavail * fs.bsize, diskTotalBytes: fs.blocks * fs.bsize };
  }
  signal?.throwIfAborted();
  return safeResult(op, result);
}
