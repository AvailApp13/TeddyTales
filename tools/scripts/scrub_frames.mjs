// Кадры таймлайна demo_moves из рантайма Rive (web): страница lab/_scrub.html грузит lab/_scrub.riv
// (оба файла не в git, см. .gitignore); запуск: NODE_PATH=<playwright> node scrub_frames.mjs "[0, 0.33, 2.6]"
import { chromium } from 'playwright';
const times = JSON.parse(process.argv[2]);
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
const errs = []; page.on('pageerror', (e) => errs.push(e.message)); page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
await page.goto(process.env.SCRUB_URL ?? 'http://127.0.0.1:4321/lab/_scrub.html', { waitUntil: 'networkidle' });
await page.evaluate(() => window.ready);
for (const t of times) { await page.evaluate((t) => window.scrubTo(t), t); await page.waitForTimeout(150); await page.locator('#c').screenshot({ path: `scrub_${Math.round(t * 60)}.png` }); }
console.log('кадров', times.length, 'ошибок', errs.length, errs.slice(0, 3));
await browser.close();
