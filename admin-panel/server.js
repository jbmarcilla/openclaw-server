const express = require('express');
const session = require('express-session');
const http = require('http');
const { WebSocketServer } = require('ws');
const pty = require('node-pty');
const bcrypt = require('bcryptjs');
const { createProxyMiddleware } = require('http-proxy-middleware');
const path = require('path');
const { loadConfig } = require('./config');

const config = loadConfig();
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

// Auth middleware
function requireAuth(req, res, next) {
  if (req.session && req.session.authenticated) return next();
  res.redirect('/login');
}

// --- Public routes ---

app.get('/login', (req, res) => {
  if (req.session && req.session.authenticated) return res.redirect('/');
  res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

app.post('/api/login', (req, res) => {
  const { username, password } = req.body;
  if (
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

// Static assets (CSS/JS accessible without auth for login page)
app.use('/css', express.static(path.join(__dirname, 'public', 'css')));
app.use('/js', express.static(path.join(__dirname, 'public', 'js')));

// --- Protected routes ---

app.post('/api/logout', requireAuth, (req, res) => {
  req.session.destroy();
  res.json({ success: true });
});

app.get('/', requireAuth, (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

// OpenClaw status check
app.get('/api/openclaw-status', requireAuth, (req, res) => {
  const check = http.get(`http://127.0.0.1:${config.openclawPort}/`, (checkRes) => {
    res.json({ running: true, status: checkRes.statusCode });
  });
  check.on('error', () => {
    res.json({ running: false });
  });
  check.setTimeout(2000, () => {
    check.destroy();
    res.json({ running: false });
  });
});

// OpenClaw reverse proxy
app.use('/openclaw', requireAuth, createProxyMiddleware({
  target: `http://127.0.0.1:${config.openclawPort}`,
  changeOrigin: true,
  pathRewrite: { '^/openclaw': '' },
  ws: true,
  on: {
    error: (err, req, res) => {
      if (res.writeHead) {
        res.status(502).json({
          error: 'OpenClaw gateway no esta corriendo',
          hint: 'Usa el terminal para ejecutar: openclaw gateway install --port 18789'
        });
      }
    }
  }
}));

// --- WebSocket terminal ---

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  // Parse session for WebSocket auth
  sessionMiddleware(request, {}, () => {
    if (!request.session || !request.session.authenticated) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    if (request.url === '/ws/terminal') {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    } else {
      socket.destroy();
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

  // PTY output -> WebSocket
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

  // WebSocket input -> PTY
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

// --- Start ---

server.listen(config.port, '127.0.0.1', () => {
  console.log(`OpenClaw Admin Panel running on http://127.0.0.1:${config.port}`);
});
