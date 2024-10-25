#ifndef NETWORK_H
#define NETWORK_H

#include "esp_websocket_client.h"
#include <Preferences.h>

extern esp_websocket_client_config_t wsConfig;
extern esp_websocket_client_handle_t wsClient;

extern Preferences preferences;

void connectToWiFi();

void connectToWebSocketServer();

#endif
