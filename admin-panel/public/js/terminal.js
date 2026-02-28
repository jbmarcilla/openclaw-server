(function () {
  'use strict';

  // --- Terminal setup ---
  var termContainer = document.getElementById('terminal-container');
  var term = new Terminal({
    cursorBlink: true,
    fontSize: 14,
    fontFamily: 'Menlo, Monaco, "Courier New", monospace',
    theme: {
      background: '#1e1e2e',
      foreground: '#cdd6f4',
      cursor: '#f5e0dc',
      selectionBackground: '#585b70',
      black: '#45475a',
      red: '#f38ba8',
      green: '#a6e3a1',
      yellow: '#f9e2af',
      blue: '#89b4fa',
      magenta: '#f5c2e7',
      cyan: '#94e2d5',
      white: '#bac2de'
    }
  });

  var fitAddon = new FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(termContainer);
  fitAddon.fit();

  // --- WebSocket connection with auto-reconnect ---
  var ws = null;
  var reconnectAttempts = 0;
  var maxReconnectAttempts = 10;
  var reconnectTimer = null;

  function connectWebSocket() {
    if (ws && (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN)) {
      return;
    }

    var protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(protocol + '//' + location.host + '/ws/terminal');

    ws.onopen = function () {
      reconnectAttempts = 0;
      var dims = fitAddon.proposeDimensions();
      if (dims) {
        ws.send(JSON.stringify({ type: 'resize', cols: dims.cols, rows: dims.rows }));
      }
    };

    ws.onmessage = function (event) {
      try {
        var msg = JSON.parse(event.data);
        if (msg.type === 'output') {
          term.write(msg.data);
        } else if (msg.type === 'exit') {
          term.writeln('\r\n[Proceso terminado]');
          scheduleReconnect();
        }
      } catch (e) {
        term.write(event.data);
      }
    };

    ws.onclose = function () {
      scheduleReconnect();
    };

    ws.onerror = function () {
      // onclose will fire after onerror, reconnect handled there
    };
  }

  function scheduleReconnect() {
    if (reconnectTimer) return;
    if (reconnectAttempts >= maxReconnectAttempts) {
      term.writeln('\r\n[No se pudo reconectar. Recarga la pagina.]');
      return;
    }

    reconnectAttempts++;
    var delay = Math.min(1000 * Math.pow(2, reconnectAttempts - 1), 15000);
    term.writeln('\r\n[Reconectando en ' + Math.round(delay / 1000) + 's...]');

    reconnectTimer = setTimeout(function () {
      reconnectTimer = null;
      connectWebSocket();
    }, delay);
  }

  // Start initial connection
  connectWebSocket();

  // Terminal input -> WebSocket
  term.onData(function (data) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'input', data: data }));
    }
  });

  // Handle resize
  function handleResize() {
    fitAddon.fit();
    var dims = fitAddon.proposeDimensions();
    if (dims && ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'resize', cols: dims.cols, rows: dims.rows }));
    }
  }
  window.addEventListener('resize', handleResize);

  // --- Tab switching ---
  var tabBtns = document.querySelectorAll('.tab-btn');
  var tabContents = document.querySelectorAll('.tab-content');

  tabBtns.forEach(function (btn) {
    btn.addEventListener('click', function () {
      tabBtns.forEach(function (b) { b.classList.remove('active'); });
      tabContents.forEach(function (c) { c.classList.remove('active'); });

      btn.classList.add('active');
      document.getElementById('tab-' + btn.dataset.tab).classList.add('active');

      if (btn.dataset.tab === 'terminal') {
        setTimeout(function () {
          fitAddon.fit();
          term.focus();
        }, 50);
      } else if (btn.dataset.tab === 'openclaw') {
        checkOpenClawStatus();
      }
    });
  });

  // --- OpenClaw status ---
  function checkOpenClawStatus() {
    var messageEl = document.getElementById('openclaw-message');
    var iframe = document.getElementById('openclaw-iframe');
    var statusContainer = document.getElementById('openclaw-status');
    var statusDot = document.getElementById('status-indicator');
    var statusText = document.getElementById('status-text');

    fetch('/api/openclaw-status')
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (data.running) {
          statusDot.className = 'status-dot online';
          statusText.textContent = 'OpenClaw Activo';
          statusContainer.style.display = 'none';
          iframe.src = '/openclaw/';
          iframe.style.display = 'block';
        } else {
          statusDot.className = 'status-dot offline';
          statusText.textContent = 'OpenClaw Detenido';
          statusContainer.style.display = 'flex';
          iframe.style.display = 'none';
          messageEl.textContent = 'OpenClaw Gateway no esta corriendo. Usa el Terminal para iniciarlo.';
        }
      })
      .catch(function () {
        statusDot.className = 'status-dot offline';
        statusText.textContent = 'Error';
        messageEl.textContent = 'No se pudo verificar el estado de OpenClaw.';
      });
  }

  document.getElementById('openclaw-refresh').addEventListener('click', checkOpenClawStatus);

  // Initial check + poll every 30s
  checkOpenClawStatus();
  setInterval(checkOpenClawStatus, 30000);

  // --- Logout ---
  document.getElementById('logoutBtn').addEventListener('click', function () {
    fetch('/api/logout', { method: 'POST' }).then(function () {
      window.location.href = '/login';
    });
  });
})();
