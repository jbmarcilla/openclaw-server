const express = require('express');
const session = require('express-session');
const http = require('http');
const { WebSocketServer } = require('ws');
const pty = require('node-pty');
const bcrypt = require('bcryptjs');
const { createProxyMiddleware } = require('http-proxy-middleware');
const path = require('path');
const { loadConfig, saveConfig, isSetupDone } = require('./config');

let config = loadConfig();
const app = express();
const server = http.createServer(app);

// Session middleware
const sessionMiddleware = session({
  secret: config.sessionSecret,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: false, // Nginx handles SSL, internal is HTTP
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000 // 24 hours
  }
});

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(sessionMiddleware);

// Trust Nginx proxy
app.set('trust proxy', 1);

// Setup check middleware - redirect to /setup if first time
function requireSetup(req, res, next) {
  if (!isSetupDone() && req.path !== '/setup' && !req.path.startsWith('/api/setup') && !req.path.startsWith('/css') && !req.path.startsWith('/js')) {
    return res.redirect('/setup');
  }
  next();
}

// Auth middleware
function requireAuth(req, res, next) {
  if (!isSetupDone()) return res.redirect('/setup');
  if (req.session && req.session.authenticated) return next();
  res.redirect('/login');
}

app.use(requireSetup);

// --- Static assets (accessible without auth for login/setup pages) ---
app.use('/css', express.static(path.join(__dirname, 'public', 'css')));
app.use('/js', express.static(path.join(__dirname, 'public', 'js')));

// --- Setup routes (first time only) ---

app.get('/setup', (req, res) => {
  if (isSetupDone()) return res.redirect('/login');
  res.sendFile(path.join(__dirname, 'public', 'setup.html'));
});

app.post('/api/setup', (req, res) => {
  if (isSetupDone()) {
    return res.status(403).json({ success: false, message: 'La cuenta ya fue creada' });
  }

  const { username, password, confirmPassword } = req.body;

  if (!username || username.length < 3) {
    return res.status(400).json({ success: false, message: 'El usuario debe tener al menos 3 caracteres' });
  }
  if (!password || password.length < 6) {
    return res.status(400).json({ success: false, message: 'La password debe tener al menos 6 caracteres' });
  }
  if (password !== confirmPassword) {
    return res.status(400).json({ success: false, message: 'Las passwords no coinciden' });
  }

  config.credentials = {
    username: username,
    passwordHash: bcrypt.hashSync(password, 10)
  };
  saveConfig(config);

  res.json({ success: true, redirect: '/login' });
});

// --- Login routes ---

app.get('/login', (req, res) => {
  if (!isSetupDone()) return res.redirect('/setup');
  if (req.session && req.session.authenticated) return res.redirect('/');
  res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

app.post('/api/login', (req, res) => {
  if (!isSetupDone()) {
    return res.status(403).json({ success: false, message: 'Primero crea tu cuenta en /setup' });
  }

  const { username, password } = req.body;
  if (
    config.credentials &&
    username === config.credentials.username &&
    bcrypt.compareSync(password, config.credentials.passwordHash)
  ) {
    req.session.authenticated = true;
    req.session.username = username;
    res.json({ success: true });
  } else {
    res.status(401).json({ success: false, message: 'Credenciales incorrectas' });
  }
});

// --- Protected routes ---

app.post('/api/logout', requireAuth, (req, res) => {
  req.session.destroy();
  res.json({ success: true });
});

app.get('/', requireAuth, (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

// Guide: detect installed tools
app.get('/api/guide-status', requireAuth, (req, res) => {
  const { execSync } = require('child_process');
  const checks = {};

  try { execSync('which openclaw', { stdio: 'ignore' }); checks.openclaw = true; } catch (e) { checks.openclaw = false; }
  try { execSync('which claude', { stdio: 'ignore' }); checks.claude = true; } catch (e) { checks.claude = false; }
  try {
    const out = execSync('openclaw gateway status 2>&1', { encoding: 'utf8', timeout: 5000 });
    checks.gateway = /running|active/i.test(out);
  } catch (e) { checks.gateway = false; }

  res.json(checks);
});

// OpenClaw status check
app.get('/api/openclaw-status', requireAuth, (req, res) => {
  let done = false;
  const finish = (data) => {
    if (done) return;
    done = true;
    try { res.json(data); } catch (e) { /* already sent */ }
  };

  try {
    const check = http.get(`http://127.0.0.1:${config.openclawPort}/`, (checkRes) => {
      checkRes.resume(); // consume response data
      finish({ running: true, status: checkRes.statusCode });
    });
    check.on('error', () => finish({ running: false }));
    check.on('timeout', () => {
      check.destroy();
      finish({ running: false });
    });
    check.setTimeout(5000);
  } catch (e) {
    finish({ running: false });
  }
});

// OpenClaw reverse proxy
app.use('/openclaw', requireAuth, createProxyMiddleware({
  target: `http://127.0.0.1:${config.openclawPort}`,
  changeOrigin: true,
  pathRewrite: { '^/openclaw': '' },
  on: {
    proxyRes: (proxyRes) => {
      // Remove headers that block iframe embedding and external resources
      delete proxyRes.headers['x-frame-options'];
      if (proxyRes.headers['content-security-policy']) {
        var csp = proxyRes.headers['content-security-policy'];
        csp = csp.replace(/frame-ancestors [^;]+;?/, "frame-ancestors 'self';");
        csp = csp.replace(/style-src ([^;]+);?/, "style-src $1 https://fonts.googleapis.com;");
        csp = csp.replace(/font-src ([^;]+);?/, "font-src $1 https://fonts.gstatic.com;");
        proxyRes.headers['content-security-policy'] = csp;
      }
    },
    error: (err, req, res) => {
      if (res.writeHead && typeof res.status === 'function') {
        res.status(502).json({
          error: 'OpenClaw gateway no esta corriendo',
          hint: 'Usa el terminal para ejecutar: openclaw gateway install --port 18789'
        });
      }
    }
  }
}));

// --- WebSocket handling ---

const wss = new WebSocketServer({ noServer: true });
const { createProxyMiddleware: _cpm } = require('http-proxy-middleware');
const openclawWsProxy = _cpm({
  target: `http://127.0.0.1:${config.openclawPort}`,
  changeOrigin: true,
  ws: true,
});

server.on('upgrade', (request, socket, head) => {
  const mockRes = Object.create(http.ServerResponse.prototype);

  sessionMiddleware(request, mockRes, () => {
    if (!request.session || !request.session.authenticated) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    if (request.url === '/ws/terminal') {
      // Terminal WebSocket
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    } else {
      // All other WebSocket connections -> OpenClaw gateway
      // (OpenClaw iframe connects to root path ws://host/, not /openclaw/)
      openclawWsProxy.upgrade(request, socket, head);
    }
  });
});

wss.on('connection', (ws) => {
  const shell = pty.spawn('bash', [], {
    name: 'xterm-256color',
    cols: 80,
    rows: 24,
    cwd: process.env.HOME || '/home/ubuntu',
    env: {
      ...process.env,
      TERM: 'xterm-256color'
    }
  });

  shell.onData((data) => {
    try {
      ws.send(JSON.stringify({ type: 'output', data }));
    } catch (e) { /* ws closed */ }
  });

  shell.onExit(({ exitCode }) => {
    try {
      ws.send(JSON.stringify({ type: 'exit', exitCode }));
      ws.close();
    } catch (e) { /* already closed */ }
  });

  ws.on('message', (msg) => {
    try {
      const message = JSON.parse(msg);
      switch (message.type) {
        case 'input':
          shell.write(message.data);
          break;
        case 'resize':
          shell.resize(message.cols, message.rows);
          break;
      }
    } catch (e) {
      shell.write(msg.toString());
    }
  });

  ws.on('close', () => {
    shell.kill();
  });
});

// Prevent unhandled errors from crashing the server
process.on('uncaughtException', (err) => {
  console.error('Uncaught exception:', err.message);
});
process.on('unhandledRejection', (err) => {
  console.error('Unhandled rejection:', err);
});

// --- Start ---

server.listen(config.port, '127.0.0.1', () => {
  console.log(`OpenClaw Admin Panel running on http://127.0.0.1:${config.port}`);
  if (!isSetupDone()) {
    console.log('First time setup: visit /setup to create your account');
  }
});
