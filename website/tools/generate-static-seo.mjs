import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const browserOutput = join(process.cwd(), 'dist', 'mizani-website', 'browser');
const shellPath = join(browserOutput, 'index.html');
const shell = await readFile(shellPath, 'utf8');

const routes = [
  {
    path: 'analysis',
    title: 'Private CSV report workspace | Mizani',
    description: 'Review a Mizani transaction CSV in your browser with local cash-flow summaries, spending breakdowns and data-quality checks.',
    robots: 'noindex, nofollow',
  },
  {
    path: 'terms',
    title: 'Website terms | Mizani',
    description: 'Read the terms for the Mizani website and its browser-local report workspace.',
  },
  {
    path: 'privacy',
    title: 'Website privacy | Mizani',
    description: 'Learn how the Mizani website and local report workspace handle your information.',
  },
];

function escapeAttribute(value) {
  return value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
}

function replaceMeta(html, attribute, key, value) {
  const tag = new RegExp(`<meta\\s+${attribute}="${key}"\\s+content="[^"]*">`);
  const replacement = `<meta ${attribute}="${key}" content="${escapeAttribute(value)}">`;
  if (!tag.test(html)) throw new Error(`Missing ${attribute} metadata for ${key}`);
  return html.replace(tag, replacement);
}

for (const route of routes) {
  let html = shell.replace(/<title>[\s\S]*?<\/title>/, `<title>${escapeAttribute(route.title)}</title>`);
  html = replaceMeta(html, 'name', 'description', route.description);
  html = replaceMeta(html, 'property', 'og:title', route.title);
  html = replaceMeta(html, 'property', 'og:description', route.description);
  html = replaceMeta(html, 'name', 'twitter:title', route.title);
  html = replaceMeta(html, 'name', 'twitter:description', route.description);
  if (route.robots) {
    html = html.replace('</head>', `    <meta name="robots" content="${route.robots}">\n  </head>`);
  }

  const routeShell = join(browserOutput, route.path, 'index.html');
  await mkdir(dirname(routeShell), { recursive: true });
  await writeFile(routeShell, html, 'utf8');
}

console.log(`Wrote static SEO shells for ${routes.map(({ path }) => `/${path}`).join(', ')}`);
