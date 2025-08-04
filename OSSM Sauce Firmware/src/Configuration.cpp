#include "Configuration.h"
#include "MotorMovement.h"

// Global variables
esp_websocket_client_config_t wsConfig;
esp_websocket_client_handle_t wsClient;
Preferences preferences;

// RGB LED variables
CRGB leds[NUM_LEDS];
unsigned long lastLEDUpdate = 0;
uint8_t breatheValue = 0;
bool breatheDirection = true;
uint8_t ledBrightness = 25;  // 0-255, adjust as needed

// LED status tracking
LEDStatus currentLEDStatus = LED_OFF;

void initializeLED() {
  FastLED.addLeds<LED_TYPE, LED_PIN, COLOR_ORDER>(leds, NUM_LEDS);
  FastLED.setBrightness(ledBrightness);
  setLEDColor(COLOR_OFF);
}


void setLEDColor(CRGB color) {
  leds[0] = color;
  FastLED.show();
}


void initializeConfiguration() {
  initializeLED();  // Initialize RGB LED first
  
  preferences.begin("ossm_sauce");

  // Set sensorless homing sensitivity
  powerAvgRangeMultiplier = preferences.getFloat("homing_trigger", 1.5);
  
  Serial.println("");
  Serial.println("=== OSSM Configuration ===");
}


void updateLED() {
  unsigned long now = millis();
  
  switch (currentLEDStatus) {
    case LED_OFF:
      setLEDColor(COLOR_OFF);
      break;
      
    case LED_WAITING_CONFIG:
      // Breathing blue effect
      if (now - lastLEDUpdate >= 20) {  // Update every 20ms for smooth breathing
        if (breatheDirection) {
          breatheValue += 2;
          if (breatheValue >= 255) {
            breatheValue = 255;
            breatheDirection = false;
          }
        } else {
          breatheValue -= 2;
          if (breatheValue <= 30) {  // Don't go completely dark
            breatheValue = 30;
            breatheDirection = true;
          }
        }
        
        leds[0] = CRGB(0, 0, breatheValue);  // Blue breathing
        FastLED.show();
        lastLEDUpdate = now;
      }
      break;
      
    case LED_CONFIG_MODE:
      // Pulsing purple
      if (now - lastLEDUpdate >= 500) {  // 500ms pulse
        static bool pulseState = false;
        pulseState = !pulseState;
        setLEDColor(pulseState ? COLOR_CONFIG : COLOR_OFF);
        lastLEDUpdate = now;
      }
      break;
      
    case LED_CONNECTING:
      setLEDColor(COLOR_CONNECTING);
      break;
      
    case LED_CONNECTED:
      // Quick green flash sequence then off
      if (now - lastLEDUpdate < 200) {
        setLEDColor(COLOR_CONNECTED);
      } else if (now - lastLEDUpdate < 400) {
        setLEDColor(COLOR_OFF);
      } else if (now - lastLEDUpdate < 600) {
        setLEDColor(COLOR_CONNECTED);
      } else if (now - lastLEDUpdate < 2000) {
        setLEDColor(COLOR_OFF);
      } else {
        lastLEDUpdate = now;  // Reset for next cycle
      }
      break;
      
    case LED_ERROR:
      // Flashing red
      if (now - lastLEDUpdate >= 300) {  // 300ms flash
        static bool errorState = false;
        errorState = !errorState;
        setLEDColor(errorState ? COLOR_ERROR : COLOR_OFF);
        lastLEDUpdate = now;
      }
      break;
  }
}


void setLEDStatus(LEDStatus status) {
  currentLEDStatus = status;
  lastLEDUpdate = millis();  // Reset timing for new status
  breatheValue = 30;  // Reset breathing animation
  breatheDirection = true;
}


bool isValidWebSocketAddress(String address) {
  // Check if port is provided
  int colonIndex = address.indexOf(':');
  
  // No port specified - add default port later
  if (colonIndex == -1) {
    address.trim();
    return address.length() > 0;
  }
  
  // Port specified - validate format
  if (colonIndex == 0 || colonIndex == address.length() - 1) {
    return false;  // Invalid format like ":port" or "host:"
  }
  
  String host = address.substring(0, colonIndex);
  String portStr = address.substring(colonIndex + 1);
  
  // Check if port is numeric and within registered range
  int port = portStr.toInt();
  if (port < 1024 || port > 49151) {
    Serial.println("Invalid port number!");
    Serial.println("Port must be within range (1024 - 49151)");
    return false;
  }
  
  // Basic host validation
  if (host.length() == 0) {
    return false;
  }
  
  return true;
}


String addDefaultPortIfMissing(String address) {
  if (address.indexOf(':') != -1) {
    return address;  // Port already specified, return as-is
  }
  
  // Add default port
  return address + ":8008";
}


bool testWebSocketConnection(String address) {
  Serial.println("Testing WebSocket connection to: " + address);
  currentLEDStatus = LED_CONNECTING;
  
  Serial.println("Testing connection with independent client...");
  
  String testUrl = "ws://" + address;
  esp_websocket_client_config_t testConfig = {.uri = testUrl.c_str()};
  esp_websocket_client_handle_t testClient = esp_websocket_client_init(&testConfig);
  
  if (!testClient) {
    Serial.println("Failed to initialize test client");
    currentLEDStatus = LED_ERROR;
    return false;
  }
  
  esp_websocket_client_start(testClient);
  
  // Wait up to 5 seconds for connection
  int attempts = 50;
  while (attempts > 0 && !esp_websocket_client_is_connected(testClient)) {
    delay(100);
    updateLED();
    attempts--;
  }
  
  bool connected = esp_websocket_client_is_connected(testClient);
  
  // Clean up test client
  esp_websocket_client_stop(testClient);
  delay(200);
  esp_websocket_client_destroy(testClient);
  delay(200);
  
  if (connected) {
    Serial.println("✓ Connection successful!");
    currentLEDStatus = LED_CONNECTED;
    delay(1000);
    return true;
  } else {
    Serial.println("✗ Connection failed!");
    currentLEDStatus = LED_ERROR;
    delay(1000);
    return false;
  }
}


String getSerialInput(String prompt) {
  Serial.println(prompt);
  while (!Serial.available()) {
    delay(100);
    updateLED();
  }
  String input = Serial.readString();
  input.trim();
  return input;
}


void showConfigMenu() {
  currentLEDStatus = LED_CONFIG_MODE;
  
  Serial.println("");
  Serial.println("=================================");
  Serial.println("       CONFIGURATION MENU");
  Serial.println("=================================");
  Serial.println("");
  
  Serial.println("Current Settings:");
  Serial.println("WiFi SSID: " + preferences.getString("wifi_ssid", "Not set"));
  Serial.println("WebSocket Server: " + preferences.getString("ws_server", "Not set"));
  Serial.println("Homing Sensitivity: " + String(powerAvgRangeMultiplier));
  Serial.println("");
  
  Serial.println("Options:");
  Serial.println("1. Show system information");
  Serial.println("2. Update WebSocket server address");
  Serial.println("3. Update WiFi credentials");
  Serial.println("4. Update sensorless homing sensitivity");
  Serial.println("5. Reverse motor direction");
  Serial.println("6. Reset all settings");
  Serial.println("7. Continue with current settings");
  Serial.println("");
  Serial.println("Enter your choice (1-7):");
}


void handleConfigMenu() {
  showConfigMenu();
  
  while (true) {
    while (!Serial.available()) {
      delay(100);
      updateLED();
    }
    
    String choice = Serial.readString();
    choice.trim();
    
    if (choice == "1") {
      // Display system information
      Serial.println("");
      Serial.println("=================================");
      Serial.println("       SYSTEM INFORMATION");
      Serial.println("=================================");
      Serial.println("");
      
      Serial.println("WiFi Network:");
      Serial.println("  SSID: " + WiFi.SSID());
      
      int rssi = WiFi.RSSI();
      Serial.println("  Signal Strength: " + String(rssi) + " dBm");
      if (rssi > -50) {
        Serial.println("    (Excellent signal)");
      } else if (rssi > -60) {
        Serial.println("    (Good signal)");
      } else if (rssi > -70) {
        Serial.println("    (Fair signal)");
      } else {
        Serial.println("    (Weak signal)");
      }
      
      Serial.println("  IP Address: " + WiFi.localIP().toString());
      Serial.println("  Gateway: " + WiFi.gatewayIP().toString());
      Serial.println("  Subnet Mask: " + WiFi.subnetMask().toString());
      Serial.println("  DNS Server: " + WiFi.dnsIP().toString());
      Serial.println("  MAC Address: " + WiFi.macAddress());
      Serial.println("  Channel: " + String(WiFi.channel()));
      Serial.println("");
      
      Serial.println("WebSocket Connection:");
      String currentServer = preferences.getString("ws_server", "Not configured");
      Serial.println("  Configured Server: " + currentServer);
      
      if (wsClient != nullptr && esp_websocket_client_is_connected(wsClient)) {
        Serial.println("  Status: ✓ Connected");
        currentLEDStatus = LED_CONNECTED;
      } else if (wsClient != nullptr) {
        Serial.println("  Status: ✗ Disconnected");
        currentLEDStatus = LED_ERROR;
      } else {
        Serial.println("  Status: Not initialized");
        currentLEDStatus = LED_ERROR;
      }
      Serial.println("");
      
      Serial.println("System Information:");
      Serial.println("  Uptime: " + String(millis() / 1000) + " seconds");
      Serial.println("  Free Heap: " + String(ESP.getFreeHeap()) + " bytes");
      Serial.println("  Chip Model: " + String(ESP.getChipModel()));
      Serial.println("  CPU Frequency: " + String(ESP.getCpuFreqMHz()) + " MHz");
      Serial.println("");
      
      delay(2000);
      currentLEDStatus = LED_CONFIG_MODE;
      
      Serial.println("Press any key to return to menu...");
      while (!Serial.available()) {
        delay(100);
        updateLED();
      }
      Serial.readString(); // Clear the input buffer
      
    } else if (choice == "2") {
      // Update WebSocket server
      String newServer = getSerialInput("Enter WebSocket server address (IP or hostname, port optional):");
      
      if (isValidWebSocketAddress(newServer)) {
        Serial.println("Validating address format... ✓");
        
        String serverWithPort = addDefaultPortIfMissing(newServer);
        
        if (serverWithPort != newServer) {
          Serial.println("No port specified, using default port 8008");
          Serial.println("Final address: " + serverWithPort);
        } else {
          Serial.println("Address format is valid!");
        }
        
        preferences.putString("ws_server", serverWithPort);
        Serial.println("WebSocket server address saved!");
        Serial.println("Device will restart to apply new WebSocket settings...");
        
        currentLEDStatus = LED_CONNECTED;
        delay(1500);
        
        ESP.restart();
      } else {
        Serial.println("Invalid address format!");
        Serial.println("Examples:");
        Serial.println("  192.168.1.100        (will use port 8008)");
        Serial.println("  192.168.1.100:8080   (custom port)");
        Serial.println("  myserver.local       (will use port 8008)");
        Serial.println("  myserver.local:3000  (custom port)");
        
        currentLEDStatus = LED_ERROR;
        delay(1000);
      }
      
    } else if (choice == "3") {
      // Update WiFi credentials
      String newSSID = getSerialInput("Enter WiFi SSID:");
      String newPassword = getSerialInput("Enter WiFi password:");
      
      preferences.putString("wifi_ssid", newSSID);
      preferences.putString("wifi_pass", newPassword);
      Serial.println("WiFi credentials updated! Device will restart to apply changes.");
      delay(2000);
      ESP.restart();
      
    } else if (choice == "4") {
      // Update sensorless homing sensitivity
      Serial.println("");
      Serial.println("Current homing sensitivity: " + String(powerAvgRangeMultiplier));
      Serial.println("Higher values = less sensitive (default: 1.5)");
      Serial.println("Lower values = more sensitive");
      Serial.println("Recommended range: 1.0 - 2.0");
      Serial.println("SETTING THIS VALUE HIGHER THAN NECESSARY CAN DAMAGE YOUR OSSM");
      Serial.println("");
      
      String newSensitivity = getSerialInput("Enter new sensitivity value:");
      float sensitivityValue = newSensitivity.toFloat();
      
      if (sensitivityValue >= 0.1 && sensitivityValue <= 10.0) {
        powerAvgRangeMultiplier = sensitivityValue;
        preferences.putFloat("homing_trigger", powerAvgRangeMultiplier);
        
        Serial.println("Homing sensitivity updated to: " + String(powerAvgRangeMultiplier));
        Serial.println("Changes will take effect on next homing cycle.");
        
        currentLEDStatus = LED_CONNECTED;
        delay(1500);
      } else {
        Serial.println("Invalid sensitivity value! Please enter a value between 0.1 and 10.0");
        currentLEDStatus = LED_ERROR;
        delay(1000);
      }
      
    } else if (choice == "5") {
      // Reverse motor direction
      bool motorDirectionReversed = preferences.getBool("motor_reversed", false);
      Serial.println("");
      Serial.println("Current motor direction: " + String(motorDirectionReversed ? "Reversed" : "Normal"));
      Serial.println("");
      Serial.println("Options:");
      Serial.println("1. Normal direction");
      Serial.println("2. Reversed direction");
      Serial.println("3. Cancel");
      Serial.println("");
      
      String directionChoice = getSerialInput("Enter your choice (1-3):");
      
      if (directionChoice == "1") {
        preferences.putBool("motor_reversed", false);
        Serial.println("Motor direction set to: Normal");
        Serial.println("Changes will take effect during next homing cycle.");
        
        currentLEDStatus = LED_CONNECTED;
        delay(1500);
        
      } else if (directionChoice == "2") {
        preferences.putBool("motor_reversed", true);
        Serial.println("Motor direction set to: Reversed");
        Serial.println("Changes will take effect during next homing cycle.");
        
        currentLEDStatus = LED_CONNECTED;
        delay(1500);
        
      } else if (directionChoice == "3") {
        Serial.println("Motor direction unchanged.");
        
      } else {
        Serial.println("Invalid choice! Motor direction unchanged.");
        currentLEDStatus = LED_ERROR;
        delay(1000);
      }
      
    } else if (choice == "6") {
      // Reset all settings
      Serial.println("Are you sure you want to reset ALL settings? (y/n)");
      String confirm = getSerialInput("");
      confirm.toLowerCase();
      if (confirm == "y") {
        preferences.clear();
        Serial.println("All settings cleared! Device will restart.");
        delay(2000);
        ESP.restart();
      }

    } else if (choice == "7") {
      // Continue with current settings
      Serial.println("Continuing with current settings...");
      break;
      
    } else {
      Serial.println("Invalid choice! Please enter 1-6.");
      continue;
    }
    
    showConfigMenu();  // Show menu again after most operations
  }
  
  currentLEDStatus = LED_OFF;
}


bool checkForConfigMode() {
  currentLEDStatus = LED_WAITING_CONFIG;
  
  Serial.println("");
  Serial.println("Press 'c' within 5 seconds to enter configuration mode...");
  
  unsigned long startTime = millis();
  while (millis() - startTime < CONFIG_TIMEOUT_MS) {
    updateLED();
    
    if (Serial.available()) {
      String input = Serial.readString();
      input.trim();
      input.toLowerCase();
      
      if (input == "c") {
        handleConfigMenu();
        return true;
      }
    }
    delay(50);
  }
  
  currentLEDStatus = LED_OFF;
  Serial.println("Continuing with startup...");
  return false;
}

void connectToWiFi() {
  WiFi.mode(WIFI_STA);
  currentLEDStatus = LED_CONNECTING;
  
  Serial.println("");
  Serial.println("-- CONNECTING TO WIFI --");
  Serial.println("--     PLEASE WAIT    --");
  Serial.println("");

  String ssid = preferences.getString("wifi_ssid");
  String password = preferences.getString("wifi_pass");
  WiFi.begin(ssid.c_str(), password.c_str());
  
  for (int i = 0; i < 10 && WiFi.status() != WL_CONNECTED; i++) {
    Serial.print(".");
    updateLED();
    delay(1000);
  }

  if (WiFi.status() != WL_CONNECTED) {
    currentLEDStatus = LED_ERROR;
    Serial.println("");
    Serial.println("No WiFi connection. Please enter WiFi credentials:");
    Serial.println("");

    String newSSID = getSerialInput("Enter WiFi SSID:");
    String newPassword = getSerialInput("Enter WiFi password:");
    
    preferences.putString("wifi_ssid", newSSID);
    preferences.putString("wifi_pass", newPassword);

    Serial.println("WiFi credentials saved. Restarting...");
    delay(1000);
    ESP.restart();
  }

  currentLEDStatus = LED_CONNECTED;
  Serial.println("");
  Serial.println("");
  Serial.println("-- WiFi connected! --");
  Serial.println("");
  delay(500);
  currentLEDStatus = LED_OFF;
}

String constructWebSocketAddress() {
  String serverAddress;
  serverAddress += "ws://";
  if (preferences.isKey("ws_server"))
    serverAddress += preferences.getString("ws_server");
  else {
    // No server configured, enter config mode
    Serial.println("No WebSocket server configured!");
    handleConfigMenu();
    // After config, try again
    if (preferences.isKey("ws_server")) {
      serverAddress += preferences.getString("ws_server");
    } else {
      Serial.println("No server configured, using localhost with port 8008");
      serverAddress += "127.0.0.1:8008";  // Fallback
    }
  }
  
  // Add default port if none specified
  if (serverAddress.indexOf(':', 5) == -1) {
    serverAddress += ":8008";
  }
  
  return serverAddress;
}


void connectToWebSocketServer() {
  String serverAddress = constructWebSocketAddress();
  currentLEDStatus = LED_CONNECTING;
  
  Serial.println("Connecting to: " + serverAddress);
  
  wsConfig = {.uri = serverAddress.c_str()};
  wsClient = esp_websocket_client_init(&wsConfig);

  if (wsClient) {
    Serial.println("WebSocket client initialized");
  } else {
    Serial.println("Failed to initialize WebSocket client");
    currentLEDStatus = LED_ERROR;
    return;
  }

  // Note: Event handler should be registered in main.cpp after calling this function
  esp_websocket_client_start(wsClient);

  // Wait for connection with LED feedback
  int attempts = 50;  // 5 seconds
  while (attempts > 0 && !esp_websocket_client_is_connected(wsClient)) {
    delay(100);
    updateLED();
    attempts--;
  }

  if (esp_websocket_client_is_connected(wsClient)) {
    Serial.println("WebSocket client connected successfully");
    currentLEDStatus = LED_CONNECTED;
    esp_websocket_client_send_text(wsClient, "Hello WebSocket", strlen("Hello WebSocket"), portMAX_DELAY);
  } else {
    Serial.println("Failed to connect to WebSocket server");
    currentLEDStatus = LED_ERROR;
    
    // Offer to enter config mode on connection failure
    Serial.println("Would you like to update the WebSocket server address? (y/n)");
    delay(4000);
    
    if (Serial.available()) {
      String input = Serial.readString();
      input.trim();
      input.toLowerCase();
      if (input == "y") {
        handleConfigMenu();
        // Try connecting again after config
        connectToWebSocketServer();
      }
    }
  }
}
