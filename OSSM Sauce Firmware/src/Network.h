#ifndef NETWORK_H
#define NETWORK_H

#include <ArduinoWebsockets.h>

using namespace websockets;
extern WebsocketsClient client;

void connectToWiFi();

void connectToWebSocketServer();

#endif
