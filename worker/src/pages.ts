import logoPng from "../../branding/logo-128.png";

const css = `
:root { color-scheme: dark; --bg: #060c18; --card: #0d1628; --text: #e8eef8; --sub: #9aa8bf; --line: #1c2a44;
  --brand: #29b9e8; --brand-soft: #0a2236; --crimson: #7a0e1c; --bad: #ff6b72; }
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px; background: var(--bg);
  color: var(--text); font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { width: 100%; max-width: 420px; background: var(--card); border: 1px solid var(--line); border-top: 3px solid var(--crimson);
  border-radius: 14px; padding: 32px 28px; }
.mark { display: flex; align-items: center; gap: 10px; font-weight: 600; font-size: 14px; color: var(--brand); margin: 0 0 20px; }
.mark img { width: 32px; height: 32px; border-radius: 8px; }
h1 { font-size: 22px; line-height: 1.25; margin: 0 0 10px; }
p { margin: 0 0 14px; color: var(--sub); }
.code { font: 600 26px/1 ui-monospace, "Cascadia Mono", Consolas, monospace; letter-spacing: 0.12em; text-align: center;
  color: var(--brand); background: var(--brand-soft); border-radius: 10px; padding: 16px; margin: 6px 0 20px; }
.button { display: block; text-align: center; text-decoration: none; font-weight: 600; color: #060c18; background: var(--brand);
  border-radius: 10px; padding: 13px 16px; margin: 8px 0 18px; }
.button:hover { background: #4fc8f0; }
ol.steps { margin: 0 0 18px; padding: 0; list-style: none; counter-reset: step; }
ol.steps li { counter-increment: step; display: grid; grid-template-columns: 28px 1fr auto; gap: 10px; align-items: baseline;
  padding: 9px 0; border-bottom: 1px solid var(--line); color: var(--sub); }
ol.steps li:last-child { border-bottom: 0; }
ol.steps li::before { content: counter(step); font-weight: 700; color: var(--brand); }
ol.steps time { font: 13px ui-monospace, "Cascadia Mono", Consolas, monospace; color: var(--sub); opacity: 0.8; }
.bad { color: var(--bad); }
form.review { display: grid; gap: 10px; margin: 0 0 18px; }
form.review input { font: inherit; padding: 10px; border-radius: 8px; border: 1px solid var(--line); background: var(--bg); color: var(--text); }
form.review button { font: inherit; font-weight: 600; padding: 11px; border-radius: 10px; border: 0; cursor: pointer; background: var(--brand); color: #060c18; }
form.review button.danger { background: var(--crimson); color: var(--text); }
.preview img, .preview video { display: block; max-width: 100%; border-radius: 10px; margin: 0 0 14px; }
.preview pre { white-space: pre-wrap; background: var(--bg); padding: 12px; border-radius: 10px; max-height: 320px; overflow: auto; }
main:has(h2) { max-width: 640px; }
main:has(video) { max-width: 860px; }
video { display: block; width: 100%; height: auto; border-radius: 10px; background: #000; margin: 6px 0 18px; }
h2 { font-size: 16px; margin: 24px 0 6px; }
a { color: var(--brand); }
b { color: var(--text); font-weight: 600; }
small { display: block; color: var(--sub); font-size: 13px; border-top: 1px solid var(--line); padding-top: 14px; }
`;

const criticalStyle = "'sha256-1iBbV+hgkHnTrR3FDJAw/2+P2baEUIuvgpuu/Hjv7Q4='";

const makeNonce = (): string => btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));

export function headers(allowForms = false, nonce = makeNonce()): Record<string, string> {
  return {
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "strict-transport-security": "max-age=63072000; includeSubDomains",
    "x-frame-options": "DENY",
    "permissions-policy": "geolocation=(), camera=(), microphone=()",
    "cross-origin-opener-policy": "same-origin",
    "referrer-policy": "no-referrer",
    "content-security-policy":
      `default-src 'none'; script-src 'self' 'nonce-${nonce}' https://static.cloudflareinsights.com; ` +
      "connect-src 'self' https://cloudflareinsights.com; img-src 'self'; media-src 'self'; font-src 'self'; " +
      `style-src 'self' 'nonce-${nonce}' ${criticalStyle}; ` +
      `base-uri 'none'; form-action ${allowForms ? "'self'" : "'none'"}; frame-ancestors 'none'`,
  };
}

export function logo(): Response {
  return new Response(logoPng, {
    headers: {
      "content-type": "image/png",
      "cache-control": "public, max-age=86400",
      "x-content-type-options": "nosniff",
      "strict-transport-security": "max-age=63072000; includeSubDomains",
    },
  });
}

export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

export function page(title: string, body: string, status = 200, allowForms = false): Response {
  const nonce = makeNonce();
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><link rel="icon" type="image/png" href="/logo.png"><title>${escapeHtml(title)} · CheckpointLTC</title><style nonce="${nonce}">${css}</style></head>
<body><main><p class="mark"><img src="/logo.png" alt="">CheckpointLTC</p>${body}</main></body></html>`;
  return new Response(html, { status, headers: headers(allowForms, nonce) });
}

export function messagePage(title: string, message: string, isError: boolean, status = 200): Response {
  return page(
    title,
    `<h1${isError ? ' class="bad"' : ""}>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p>`,
    status,
  );
}

const storeLink = "https://create.roblox.com/store/asset/104522423965573";
const discordLink = "https://discord.gg/5njkCsBdNd";

export function legalPage(title: string, lead: string, summary: string[], body: string, other: { href: string; label: string }): Response {
  const toc: string[] = [];
  const sections = body.replace(/<h2>([^<]+)<\/h2>/g, (_match, text: string) => {
    const id = text.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
    toc.push(`<a href="#${id}">${text}</a>`);
    return `<h2 id="${id}">${text}</h2>`;
  });
  const words = title.split(" ");
  const last = words.pop() ?? "";
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} · CheckpointLTC</title>
<meta name="description" content="${escapeHtml(`The CheckpointLTC ${title.toLowerCase()}, in plain words.`)}">
<meta name="theme-color" content="#29b9e8">
<link rel="icon" type="image/png" href="/site/icon.png">
<link rel="preload" href="/site/fonts/bricolage.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/site/site.css?v=7">
<script src="/site/legal.js?v=5" defer></script>
</head>
<body class="doc-page">
<div class="grid" aria-hidden="true"></div>
<header class="top">
  <a class="brand" href="/"><img src="/site/icon.png" alt="" width="28" height="28"><span>CheckpointLTC</span></a>
  <nav>
    <a href="/#demo">Try it</a>
    <a href="/#features">Features</a>
    <a class="keep" href="/guide">Guide</a>
    <a href="/#discord">Discord</a>
    <a class="get" href="${storeLink}" target="_blank" rel="noopener">Get the plugin</a>
    <details class="menu"><summary aria-label="Menu"><i></i><i></i><i></i></summary><div class="menu-panel"><a href="/#demo">Try it</a><a href="/#features">Features</a><a href="/guide">Guide</a><a href="/#discord">Discord</a></div></details>
  </nav>
</header>
<main>
  <section class="doc in">
    <h1>${escapeHtml(words.join(" "))} <span class="scribble">${escapeHtml(last)}.<svg viewBox="0 0 400 24" preserveAspectRatio="none" aria-hidden="true"><path d="M3 14 C 70 6, 140 19, 210 12 S 330 7, 397 12"></path></svg></span></h1>
    <p class="lede">${escapeHtml(lead)}</p>
    <div class="short">
      <h2>The short version</h2>
      <ul class="ticks">${summary.map((line) => `<li>${escapeHtml(line)}</li>`).join("")}</ul>
    </div>
    <div class="doc-grid">
      <nav class="toc" aria-label="On this page"><p>On this page</p>${toc.join("")}</nav>
      <article class="doc-body">${sections}</article>
    </div>
    <div class="doc-end">
      <h2>Questions?</h2>
      <p class="sub">Ask me directly in my Discord, that's the fastest way to reach me.</p>
      <div class="actions">
        <a class="button discord" href="${discordLink}" target="_blank" rel="noopener">Ask in Discord</a>
        <a class="button" href="${other.href}">${escapeHtml(other.label)}</a>
      </div>
    </div>
  </section>
</main>
<footer class="foot">
  <span>Made by LTCLevTec LLC</span>
  <span><a href="/">Home</a> · <a href="/guide">Guide</a> · <a href="${discordLink}" target="_blank" rel="noopener">Discord</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a></span>
</footer>
</body>
</html>`;
  return new Response(html, { headers: headers() });
}
