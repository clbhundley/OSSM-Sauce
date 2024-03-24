const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 120 });

wss.on('connection', ws => {
  ws.on('message', message => {
    console.log(`Received message => ${message}`);
    // Send the message to all connected clients
    wss.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(message);
      }
    });
  });
});
