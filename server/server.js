const { WebSocketServer } = require('ws');
const http = require('http');
const url = require('url');
const crypto = require('crypto');

const PORT = process.env.PORT || 9877;
const PING_INTERVAL = 30000;

// Store connected clients: deviceId -> { ws, deviceName, platform }
const clients = new Map();
// Track which device IDs are online
const deviceRegistry = new Map();

function createServer() {
  const server = http.createServer((req, res) => {
    // Health check endpoint
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'ok',
        clients: clients.size,
        devices: Array.from(deviceRegistry.keys()),
      }));
      return;
    }
    // Status page
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`<h1>Clipboard Sync Relay</h1>
<p>Connected devices: ${clients.size}</p>
<ul>${Array.from(deviceRegistry.entries()).map(([id, info]) => 
  `<li>${info.name} (${info.platform}) - ${info.since}</li>`
).join('')}</ul>`);
  });

  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws, req) => {
    let deviceId = null;
    let deviceName = 'Unknown';
    let platform = 'unknown';
    let isAlive = true;

    // Ping/pong keepalive
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());

        if (message.type === 'handshake') {
          // Register client
          deviceId = message.senderId;
          deviceName = message.senderName || 'Unknown';
          platform = message.platform || 'unknown';

          clients.set(deviceId, { ws, deviceName, platform });
          deviceRegistry.set(deviceId, {
            name: deviceName,
            platform: platform,
            since: new Date().toISOString(),
          });

          console.log(`[+] ${deviceName} (${deviceId}) connected. Total: ${clients.size}`);

          // Notify all other clients about this new device
          broadcastToAll(deviceId, {
            type: 'peer_joined',
            senderId: deviceId,
            senderName: deviceName,
            platform: platform,
            timestamp: Date.now(),
          });

          // Send current peer list to the newly connected device
          const peerList = Array.from(deviceRegistry.entries())
            .filter(([id]) => id !== deviceId)
            .map(([id, info]) => ({
              senderId: id,
              senderName: info.name,
              platform: info.platform,
            }));

          if (peerList.length > 0) {
            sendTo(ws, {
              type: 'peer_list',
              senderId: 'relay',
              peers: peerList,
              timestamp: Date.now(),
            });
          }

        } else if (message.type === 'clipboard_sync' && deviceId) {
          // Relay clipboard data to all OTHER connected clients
          broadcastToAll(deviceId, message);
          console.log(`[→] ${deviceName}: ${message.payload?.contentType || 'unknown'} (${(message.payload?.data?.length || 0)} bytes)`);
        }
      } catch (e) {
        console.error('Message error:', e.message);
      }
    });

    ws.on('close', () => {
      if (deviceId) {
        clients.delete(deviceId);
        deviceRegistry.delete(deviceId);
        console.log(`[-] ${deviceName} (${deviceId}) disconnected. Total: ${clients.size}`);

        // Notify others
        broadcastToAll(deviceId, {
          type: 'peer_left',
          senderId: deviceId,
          senderName: deviceName,
          timestamp: Date.now(),
        });
      }
    });

    ws.on('error', (err) => {
      console.error(`WebSocket error for ${deviceName}:`, err.message);
    });
  });

  // Ping all clients periodically
  const pingTimer = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.isAlive === false) return ws.terminate();
      ws.isAlive = false;
      ws.ping();
    });
  }, PING_INTERVAL);

  wss.on('close', () => clearInterval(pingTimer));

  server.listen(PORT, () => {
    console.log(`========================================`);
    console.log(`  Clipboard Sync Relay Server`);
    console.log(`  Listening on port ${PORT}`);
    console.log(`  WebSocket: ws://0.0.0.0:${PORT}`);
    console.log(`  Health:    http://0.0.0.0:${PORT}/health`);
    console.log(`========================================`);
  });
}

function broadcastToAll(senderId, message) {
  const json = JSON.stringify(message);
  clients.forEach((client, id) => {
    if (id !== senderId && client.ws.readyState === 1) {
      try {
        client.ws.send(json);
      } catch (e) {
        console.error(`Broadcast error to ${id}:`, e.message);
      }
    }
  });
}

function sendTo(ws, message) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(message));
  }
}

createServer();
