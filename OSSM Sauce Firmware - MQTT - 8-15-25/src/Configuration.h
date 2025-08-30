#ifndef CONFIGURATION_H
#define CONFIGURATION_H

#include <WiFi.h>
#include <Preferences.h>
#include <FastLED.h>
#include "esp_websocket_client.h"

#define CONFIG_TIMEOUT_MS 5000

// RGB LED configuration
#define LED_PIN 25
#define NUM_LEDS 1
#define LED_TYPE WS2812B
#define COLOR_ORDER GRB

// LED status colors
#define COLOR_OFF        CRGB::Black
#define COLOR_WAITING    CRGB::Blue         // Waiting for config input
#define COLOR_CONFIG     CRGB::Purple       // In configuration mode
#define COLOR_CONNECTING CRGB::Orange       // Connecting to WiFi/WebSocket
#define COLOR_CONNECTED  CRGB::Green        // Successfully connected
#define COLOR_ERROR      CRGB::Red          // Error/connection failed

// LED status indicators
enum LEDStatus {
  LED_OFF,
  LED_WAITING_CONFIG,    // Breathing blue
  LED_CONFIG_MODE,       // Pulsing purple
  LED_CONNECTING,        // Solid orange
  LED_CONNECTED,         // Green flash sequence
  LED_ERROR              // Flashing red
};

// Global variables
extern esp_websocket_client_config_t wsConfig;
extern esp_websocket_client_handle_t wsClient;
extern Preferences preferences;
extern CRGB leds[NUM_LEDS];

// Configuration and connection functions
void initializeConfiguration();
bool checkForConfigMode();
void connectToWiFi();
void connectToWebSocketServer();

// LED control functions
void initializeLED();
void setLEDColor(CRGB color);
void updateLED();
void setLEDStatus(LEDStatus status);

// Configuration menu functions
void handleConfigMenu();
bool isValidWebSocketAddress(String address);

#endif