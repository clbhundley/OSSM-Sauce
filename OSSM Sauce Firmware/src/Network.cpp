#include <Preferences.h>
#include <WiFi.h>
#include "Network.h"

Preferences preferences;

using namespace websockets;
WebsocketsClient client;


void connectToWiFi() {
  WiFi.mode(WIFI_STA);
  Serial.println("");
  Serial.println("-- CONNECTING TO WIFI --");
  Serial.println("--     PLEASE WAIT    --");
  Serial.println("");

  preferences.begin("ossm_sauce");

  String ssid = preferences.getString("wifi_ssid");
  String password = preferences.getString("wifi_pass");
  WiFi.begin(ssid.c_str(), password.c_str());
  for (int i = 0; i < 10 && WiFi.status() != WL_CONNECTED; i++) {
    Serial.print(".");
    delay(1000);
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("");
    Serial.println("No WiFi connection. Please enter WiFi credentials:");
    Serial.println("");

    Serial.println("Enter WiFi SSID: ");
    while (!Serial.available()) {
      delay(100); // Wait for user input
    }
    ssid = Serial.readString();
    ssid.trim();
    preferences.putString("wifi_ssid", ssid);

    Serial.println("Enter WiFi password: ");
    while (!Serial.available()) {
      delay(100); // Wait for user input
    }
    password = Serial.readString();
    password.trim();
    preferences.putString("wifi_pass", password);

    preferences.end();
    ESP.restart();
    delay(1000);
  }

  Serial.println("");
  Serial.println("");
  Serial.println("-- WiFi connected! --");
  Serial.println("");
}


bool wsConnect(String serverAddress) {
  String address;
  int port = 120;
  size_t colonPosition = serverAddress.indexOf(':');
  if (colonPosition > -1) {
      address = serverAddress.substring(0, colonPosition);
      port = serverAddress.substring(colonPosition + 1).toInt();
  } else {
      address = serverAddress;
  }
  return client.connect(address.c_str(), port, "/");
}


void connectToWebSocketServer() {
  String wsServerAddress = preferences.getString("ws_server");
  
  if (!wsConnect(wsServerAddress)) {
    Serial.println("");
    Serial.println("Enter WebSocket server address: ");
    while (!Serial.available()) {
      delay(100); // Wait for user input
    }
    wsServerAddress = Serial.readString();
    wsServerAddress.trim();
    preferences.putString("ws_server", wsServerAddress);
  }

  Serial.println("");

  if (wsConnect(wsServerAddress)) {
    Serial.println("-- Connected to WebSocket server! --");
    Serial.println("");
  } else {
    Serial.println("Failed to connect to WebSocket server!");
    preferences.end();
    ESP.restart();
    delay(1000);
  }
}
