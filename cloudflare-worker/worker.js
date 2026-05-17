/**
 * Cloudflare Worker for install.jarviscli.dev
 * 
 * curl -sSL https://install.jarviscli.dev | sudo bash   → serves install.sh
 * Browser visit                                          → shows landing page
 */

const SCRIPT_URL = 'https://raw.githubusercontent.com/everestmcarthur/pelican-installer/main/install.sh';

function isCurl(request) {
  const ua = (request.headers.get('User-Agent') || '').toLowerCase();
  const accept = (request.headers.get('Accept') || '');
  return ua.includes('curl') || ua.includes('wget') || ua.includes('httpie') ||
    ua.includes('powershell') || !accept.includes('text/html');
}

async function serveScript() {
  const resp = await fetch(SCRIPT_URL, {
    cf: { cacheTtl: 300, cacheEverything: true }
  });

  if (!resp.ok) {
    return new Response('#!/bin/bash\necho "Error: Could not fetch installer. Try: curl -sSL https://raw.githubusercontent.com/everestmcarthur/pelican-installer/main/install.sh | sudo bash"\nexit 1', {
      status: 502,
      headers: { 'Content-Type': 'text/plain' }
    });
  }

  const script = await resp.text();
  return new Response(script, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
      'X-Content-Type-Options': 'nosniff'
    }
  });
}

function serveLanding() {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pelican Installer — install.jarviscli.dev</title>
  <style>
    :root { --bg: #0f172a; --card: #1e293b; --border: #334155; --text: #e2e8f0; --dim: #94a3b8; --accent: #38bdf8; --green: #4ade80; --purple: #a78bfa; }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', monospace; background: var(--bg); color: var(--text); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 2rem; }
    .container { max-width: 680px; width: 100%; }
    h1 { font-size: 2rem; margin-bottom: 0.5rem; }
    h1 span { color: var(--accent); }
    .subtitle { color: var(--dim); margin-bottom: 2rem; font-size: 0.95rem; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 1.5rem; margin-bottom: 1.5rem; }
    .card-title { color: var(--accent); font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 1rem; }
    .cmd { background: #0d1117; border: 1px solid var(--border); border-radius: 8px; padding: 1rem 1.25rem; font-size: 0.95rem; position: relative; cursor: pointer; transition: border-color 0.2s; overflow-x: auto; }
    .cmd:hover { border-color: var(--accent); }
    .cmd code { color: var(--green); white-space: nowrap; }
    .cmd .copy-hint { position: absolute; right: 12px; top: 50%; transform: translateY(-50%); color: var(--dim); font-size: 0.75rem; opacity: 0; transition: opacity 0.2s; }
    .cmd:hover .copy-hint { opacity: 1; }
    .cmd.copied .copy-hint { color: var(--green); opacity: 1; }
    .features { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
    .feature { display: flex; align-items: start; gap: 0.5rem; font-size: 0.85rem; color: var(--dim); }
    .feature::before { content: '✓'; color: var(--green); font-weight: bold; flex-shrink: 0; }
    .links { display: flex; gap: 1rem; margin-top: 1.5rem; }
    .links a { color: var(--accent); text-decoration: none; font-size: 0.85rem; }
    .links a:hover { text-decoration: underline; }
    .version { color: var(--purple); font-size: 0.8rem; margin-top: 1.5rem; text-align: center; }
    @media (max-width: 600px) { .features { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <div class="container">
    <h1>🐦 <span>Pelican Installer</span></h1>
    <p class="subtitle">The best way to install Pelican Panel &amp; Wings — one command, fully automated.</p>
    <div class="card">
      <div class="card-title">Quick Install</div>
      <div class="cmd" onclick="copyCmd(this, 'curl -sSL https://install.jarviscli.dev | sudo bash')">
        <code>curl -sSL https://install.jarviscli.dev | sudo bash</code>
        <span class="copy-hint">click to copy</span>
      </div>
    </div>
    <div class="card">
      <div class="card-title">Or with options</div>
      <div class="cmd" onclick="copyCmd(this, 'curl -sSL https://install.jarviscli.dev | sudo bash -s -- install --panel --domain panel.example.com --webserver nginx --database postgres --ssl --email you@example.com --cache-driver redis --session-driver redis --queue-driver redis --admin-email admin@example.com --admin-user admin --admin-pass MyPassword -y')">
        <code>curl -sSL https://install.jarviscli.dev | sudo bash -s -- install \\<br>  --panel --domain panel.example.com --webserver nginx \\<br>  --database postgres --ssl --email you@example.com \\<br>  --cache-driver redis --session-driver redis \\<br>  --queue-driver redis --admin-email admin@example.com \\<br>  --admin-user admin --admin-pass MyPassword -y</code>
        <span class="copy-hint">click to copy</span>
      </div>
    </div>
    <div class="card">
      <div class="card-title">Features</div>
      <div class="features">
        <div class="feature">Nginx, Apache &amp; Caddy</div>
        <div class="feature">MySQL, MariaDB, PostgreSQL, SQLite</div>
        <div class="feature">Auto SSL via Let's Encrypt</div>
        <div class="feature">Redis cache, session &amp; queue</div>
        <div class="feature">Wings reverse proxy (all 3 web servers)</div>
        <div class="feature">Fully non-interactive mode</div>
        <div class="feature">Auto admin user creation</div>
        <div class="feature">Post-install health checks</div>
        <div class="feature">Update &amp; uninstall commands</div>
        <div class="feature">ARM64 support</div>
      </div>
    </div>
    <div class="links">
      <a href="https://github.com/everestmcarthur/pelican-installer">📦 GitHub</a>
      <a href="https://github.com/everestmcarthur/pelican-installer#readme">📖 Docs</a>
      <a href="https://github.com/everestmcarthur/pelican-installer/issues">🐛 Issues</a>
    </div>
    <p class="version">Powered by JarvisCLI</p>
  </div>
  <script>
    function copyCmd(el, text) {
      navigator.clipboard.writeText(text);
      el.classList.add('copied');
      el.querySelector('.copy-hint').textContent = 'copied!';
      setTimeout(() => { el.classList.remove('copied'); el.querySelector('.copy-hint').textContent = 'click to copy'; }, 2000);
    }
  </script>
</body>
</html>`;
  return new Response(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' }
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === '/install.sh' || url.pathname === '/script') {
      return serveScript();
    }

    if (url.pathname === '/' || url.pathname === '') {
      if (isCurl(request)) {
        return serveScript();
      }
      return serveLanding();
    }

    return new Response('Not Found', { status: 404 });
  }
};
