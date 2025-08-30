#include <Arduino.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "MotorMovement.h"
#include "Configuration.h"
#include <WiFi.h>
#include <PubSubClient.h>

// MQTT Configuration  
const char* mqtt_broker = "192.168.254.64";
const int mqtt_port = 1883;  // Try standard port first
const char* topic_ossm_position = "ossm/position";
const char* topic_ossm_command = "ossm/command";
const char* topic_ossm_status = "ossm/status";

// MQTT Objects
WiFiClient mqttWifiClient;
PubSubClient mqttClient(mqttWifiClient);
unsigned long lastMqttReconnectAttempt = 0;
const unsigned long mqttReconnectInterval = 5000; // Try reconnecting every 5 seconds

unsigned long playStartTime;
unsigned long playTimeMs;

StrokeCommand activeMove;

StrokeCommand loopPush;
StrokeCommand loopPull;

QueueHandle_t moveQueue;
const char moveQueueSize = 10;
bool moveQueueIsEmpty = true;

QueueHandle_t positionQueue;
const char positionQueueSize = 50;
bool positionQueueIsEmpty = true;
int previousTargetPosition;

StrokeCommand smoothMoveCommand;
unsigned long smoothMoveStartTime;
bool smoothMoveActive = false;

enum CommandType:byte {
  RESPONSE,
  MOVE,
  LOOP,
  POSITION,
  VIBRATE,
  PLAY,
  PAUSE,
  RESET,
  HOMING,
  CONNECTION,
  SET_SPEED_LIMIT,
  SET_GLOBAL_ACCELERATION,
  SET_RANGE_LIMIT,
  SET_HOMING_SPEED,
  SET_HOMING_TRIGGER,
  SMOOTH_MOVE,  // 0x0F
};

struct Response {
  CommandType commandType = RESPONSE;
  CommandType responseType;
};

// MQTT Functions
void mqttReconnect() {
  if (millis() - lastMqttReconnectAttempt > mqttReconnectInterval) {
    lastMqttReconnectAttempt = millis();
    
    Serial.print("Attempting MQTT connection to ");
    Serial.print(mqtt_broker);
    Serial.print(":");
    Serial.println(mqtt_port);
    
    // Check WiFi status
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("WiFi not connected!");
      return;
    }
    
    // Test basic connectivity
    Serial.print("Testing connectivity to ");
    Serial.print(mqtt_broker);
    Serial.print("...");
    WiFiClient testClient;
    if (testClient.connect(mqtt_broker, mqtt_port)) {
      Serial.println(" ✓ TCP connection successful");
      testClient.stop();
    } else {
      Serial.println(" ✗ TCP connection failed!");
      
      // Test gateway connectivity
      Serial.print("Testing gateway connectivity...");
      if (testClient.connect(WiFi.gatewayIP().toString().c_str(), 80)) {
        Serial.println(" ✓ Gateway reachable");
        testClient.stop();
      } else {
        Serial.println(" ✗ Gateway unreachable");
      }
      
      // Test Google DNS
      Serial.print("Testing internet connectivity...");
      if (testClient.connect("8.8.8.8", 53)) {
        Serial.println(" ✓ Internet reachable");
        testClient.stop();
      } else {
        Serial.println(" ✗ Internet unreachable");
      }
      
      Serial.println("Check if ESP32 and broker are on same network");
      return;
    }
    
    String clientId = "OSSM-ESP32-";
    clientId += String(random(0xffff), HEX);
    Serial.print("Using client ID: ");
    Serial.println(clientId);
    
    if (mqttClient.connect(clientId.c_str())) {
      Serial.println("✓ Connected to MQTT Broker");
      
      // Subscribe to topics
      if (mqttClient.subscribe(topic_ossm_position)) {
        Serial.println("✓ Subscribed to position topic");
      } else {
        Serial.println("✗ Failed to subscribe to position topic");
      }
      
      if (mqttClient.subscribe(topic_ossm_command)) {
        Serial.println("✓ Subscribed to command topic");
      } else {
        Serial.println("✗ Failed to subscribe to command topic");
      }
      
      // Publish status
      if (mqttClient.publish(topic_ossm_status, "connected")) {
        Serial.println("✓ Published status message");
      } else {
        Serial.println("✗ Failed to publish status message");
      }
    } else {
      int state = mqttClient.state();
      Serial.print("✗ MQTT connection failed, rc=");
      Serial.print(state);
      Serial.print(" (");
      switch(state) {
        case -4: Serial.print("TIMEOUT"); break;
        case -3: Serial.print("CONNECTION_LOST"); break;
        case -2: Serial.print("CONNECT_FAILED"); break;
        case -1: Serial.print("DISCONNECTED"); break;
        case 1: Serial.print("BAD_PROTOCOL"); break;
        case 2: Serial.print("BAD_CLIENT_ID"); break;
        case 3: Serial.print("UNAVAILABLE"); break;
        case 4: Serial.print("BAD_CREDENTIALS"); break;
        case 5: Serial.print("UNAUTHORIZED"); break;
        default: Serial.print("UNKNOWN"); break;
      }
      Serial.println(")");
    }
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String topicString = String(topic);
  
  // Convert payload to string for text messages
  char* payloadStr = new char[length + 1];
  memcpy(payloadStr, payload, length);
  payloadStr[length] = '\0';  // Null terminate
  String messageText = String(payloadStr);
  delete[] payloadStr;  // Clean up allocated memory
  
  Serial.println("=== MQTT Message Received ===");
  Serial.print("Topic: ");
  Serial.println(topicString);
  Serial.print("Length: ");
  Serial.println(length);
  Serial.print("Text Content: ");
  Serial.println(messageText);
  Serial.println("============================");
  
  if (topicString == topic_ossm_position) {
    // Handle position commands from Node-RED slider
    if (length > 0) {
      // Convert string to integer
      u32_t inputPosition = messageText.toInt();
      
      Serial.print("Parsed position value: ");
      Serial.println(inputPosition);
      
      // Apply the same logic as the WebSocket POSITION case
      int constrainedPosition = constrain(inputPosition, 0, 10000);
      int targetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
      int positionDelta = targetPosition - previousTargetPosition;
      int currentPosition = stepper->getCurrentPosition();
      
      bool lockedMin = targetPosition < currentPosition && positionDelta > 0;
      bool lockedMax = targetPosition > currentPosition && positionDelta < 0;
      
      Serial.print("Target position: ");
      Serial.println(targetPosition);
      Serial.print("Current position: ");
      Serial.println(currentPosition);
      Serial.print("Position delta: ");
      Serial.println(positionDelta);
      
      previousTargetPosition = targetPosition;
      
      if (lockedMin || lockedMax) {
        Serial.println("Movement locked due to direction constraints");
      } else {
        u32_t speed = abs(positionDelta) * 50;
        u32_t finalSpeed = min(speed, globalSpeedLimitHz);
        
        Serial.print("Setting speed: ");
        Serial.println(finalSpeed);
        
        stepper->setSpeedInHz(finalSpeed);
        stepper->moveTo(targetPosition);
        processSafeAccel();
        
        Serial.println("Motor movement command sent");
      }
    }
  } else if (topicString == topic_ossm_command) {
    // Handle other commands - expect full binary command format
    if (length > 0) {
      esp_websocket_event_data_t fakeData;
      fakeData.data_ptr = (char*)payload;
      fakeData.data_len = length;
      
      Serial.println("Processing binary command");
      //parseMessage(&fakeData);
    }
  } else {
    // Handle any other topics as text messages
    Serial.println("Processing as text message");
    // You could add specific text message handling here
  }
}

void setupMQTT() {
  // Print network debugging info
  Serial.println("=== Network Debug Info ===");
  Serial.print("ESP32 IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("ESP32 Subnet: ");
  Serial.println(WiFi.subnetMask());
  Serial.print("ESP32 Gateway: ");
  Serial.println(WiFi.gatewayIP());
  Serial.print("MQTT Broker: ");
  Serial.print(mqtt_broker);
  Serial.print(":");
  Serial.println(mqtt_port);
  Serial.println("========================");
  
  mqttClient.setServer(mqtt_broker, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setKeepAlive(15);  // Optimize for streaming
  mqttClient.setSocketTimeout(5);  // Increase socket timeout for debugging
}

void moveStart() {
  activeMove.active = false;
  short lastTargetDepth = activeMove.depth;
  if (!xQueueReceive(moveQueue, &activeMove, (TickType_t)10))
    Serial.println("ERROR: Queue empty.");
  if (activeMove.endTimeMs == 0 && uxQueueSpacesAvailable(moveQueue) < moveQueueSize) { // start of next path
    playTimeMs = 0;
    playStartTime = millis();
  } else if (activeMove.endTimeMs == 0 || activeMove.depth == lastTargetDepth)
    return;
  short constrainedPosition = constrain(activeMove.depth, 0, 10000);
  activeMove.targetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
  activeMove.playTimeStartedMs = playTimeMs;
  u32_t durationMs = activeMove.endTimeMs - activeMove.playTimeStartedMs;
  activeMove.durationReciprocal = 1.0 / durationMs;
  activeMove.baseSpeedHz = getMoveBaseSpeedHz(activeMove, durationMs);
  activeMove.active = true;
}

void sendResponse(CommandType responseCommand) {
  Response responseMessage;
  int messageSize = sizeof(responseMessage);
  responseMessage.responseType = responseCommand;
  char message[messageSize];
  memcpy(message, (char*)&responseMessage, messageSize);
  
  // Send via WebSocket if connected
  if (wsClient) {
    esp_websocket_client_send_bin(wsClient, message, messageSize, portMAX_DELAY);
  }
  
  // Send via MQTT if connected
  if (mqttClient.connected()) {
    mqttClient.publish(topic_ossm_status, message, messageSize);
  }
}

void parseMessage(esp_websocket_event_data_t *data) {
  byte* message = (byte*)data->data_ptr;
  size_t messageLength = data->data_len;

  if (movementMode == MODE_HOMING)
    return;
  
  CommandType commandType = static_cast<CommandType>(message[0]);
  switch (commandType) {
    case RESPONSE:
      break;

    case MOVE: {
      if (messageLength != 10)
        break;
      if(!xQueueSend(moveQueue, &(message[1]), (TickType_t)10))
        Serial.println("ERROR: Failed to add move command to queue. Is queue full?");
      if (moveQueueIsEmpty)
        moveStart();
      moveQueueIsEmpty = false;
      break;
    }

    case LOOP: {
      if (messageLength != 19)
        break;
      
      memcpy(&loopPush, message + 1, 9);
      memcpy(&loopPull, message + 10, 9);
      
      if (loopPush.endTimeMs != 0) {
        short constrainedPosition = constrain(loopPush.depth, 0, 10000);
        //loopPush.targetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
        loopPush.targetPosition = rangeLimitUserMax;
        loopPush.durationReciprocal = 1.0 / loopPush.endTimeMs;
        loopPush.baseSpeedHz = getMoveBaseSpeedHz(loopPush, loopPush.endTimeMs, true);
      }
      if (loopPull.endTimeMs != 0) {
        short constrainedPosition = constrain(loopPull.depth, 0, 10000);
        //loopPull.targetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
        loopPull.targetPosition = rangeLimitUserMin;
        loopPull.durationReciprocal = 1.0 / loopPull.endTimeMs;
        loopPull.baseSpeedHz = getMoveBaseSpeedHz(loopPull, loopPull.endTimeMs, true);
      }
      movementMode = MODE_LOOP;
      break;
    }

    case POSITION: {
      // if (movementMode != MODE_POSITION)
        // break;
      u32_t inputPosition;
      memcpy(&inputPosition, message + 1, 4);
      int constrainedPosition = constrain(inputPosition, 0, 10000);
      int targetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
      int positionDelta = targetPosition - previousTargetPosition;
      int currentPosition = stepper->getCurrentPosition();
      bool lockedMin = targetPosition < currentPosition && positionDelta > 0;
      bool lockedMax = targetPosition > currentPosition && positionDelta < 0;
      previousTargetPosition = targetPosition;
      if (lockedMin || lockedMax)
        break;
      u32_t speed = abs(positionDelta) * 50;
      stepper->setSpeedInHz(min(speed, globalSpeedLimitHz));
      stepper->moveTo(targetPosition);
      processSafeAccel();
      break;
    }

    case VIBRATE: {
      if (messageLength != 13)
        break;
      memcpy(&vibration, message + 1, 12);

      int constrainedPosition = constrain(vibration.position, 0, 10000);
      vibration.origin = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
      uint32_t totalRange = abs(rangeLimitUserMax - rangeLimitUserMin);
      uint32_t vibrationRange = vibration.rangePercent * 0.01 * totalRange;
      long vibrationEndpoint = vibration.origin + vibrationRange;
      vibration.crest = constrain(vibrationEndpoint, rangeLimitUserMin, rangeLimitUserMax);

      float halfPeriodReciprocal = 1 / float(vibration.halfPeriodMs);
      uint32_t duration = 1000 * halfPeriodReciprocal;
      float waveformSpeedScaling = vibration.speedScaling * 0.01;
      uint32_t newSpeed = vibrationRange * duration * waveformSpeedScaling;
      stepper->setSpeedInHz(min(newSpeed, globalSpeedLimitHz));

      if (vibration.duration > 0) {
        vibration.timed = true;
        vibration.endMs = millis() + vibration.duration;
      } else if (vibration.duration < 0) {
        vibration.timed = false;
      } else {
        movementMode = MODE_IDLE;
        break;
      }

      processSafeAccel();
      movementMode = MODE_VIBRATE;
      break;
    }

    case PLAY: {
      memcpy(&movementMode, message + 1, 1);
      if (messageLength == 6) {
        memcpy(&playTimeMs, message + 2, 4);
      }
      playStartTime = millis() - playTimeMs;
      break;
    }

    case PAUSE: {
      movementMode = MODE_IDLE;
      break;
    }

    case RESET: {
      movementMode = MODE_IDLE;
      playTimeMs = 0;
      xQueueReset(moveQueue);
      xQueueReset(positionQueue);
      moveQueueIsEmpty = true;
      break;
    }

    case HOMING: {
      u32_t inputPosition;
      memcpy(&inputPosition, message + 1, 4);
      int constrainedPosition = constrain(inputPosition, 0, 10000);
      homingTargetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
      movementMode = MODE_HOMING;
      break;
    }

    case CONNECTION: {
      sendResponse(CONNECTION);
      break;
    }

    case SET_SPEED_LIMIT: {
      int speedLimit;
      memcpy(&speedLimit, message + 1, 4);
      globalSpeedLimitHz = max(speedLimit, 0);
      break;
    }

    case SET_GLOBAL_ACCELERATION: {
      int acceleration;
      memcpy(&acceleration, message + 1, 4);
      globalAcceleration = max(acceleration, 0);
      break;
    }

    case SET_RANGE_LIMIT: {
      short rangeLimitInput;
      memcpy(&rangeLimitInput, message + 2, 2);
      rangeLimitInput = constrain(rangeLimitInput, 0, 10000);
      rangeLimitInput = map(rangeLimitInput, 0, 10000, rangeLimitHardMin, rangeLimitHardMax);
      byte selectedRange = message[1];
      enum {MIN_RANGE, MAX_RANGE};
      switch (selectedRange) {
        case MIN_RANGE:
          rangeLimitUserMin = rangeLimitInput;
          break;
        case MAX_RANGE:
          rangeLimitUserMax = rangeLimitInput;
          break;
      }
      if (movementMode == MODE_LOOP) {
        if (loopPush.endTimeMs != 0) {
          loopPush.targetPosition = rangeLimitUserMax;
          loopPush.baseSpeedHz = getMoveBaseSpeedHz(loopPush, loopPush.endTimeMs, true);
        }
        if (loopPull.endTimeMs != 0) {
          loopPull.targetPosition = rangeLimitUserMin;
          loopPull.baseSpeedHz = getMoveBaseSpeedHz(loopPull, loopPull.endTimeMs, true);
        }
      }
      break;
    }

    case SET_HOMING_SPEED: {
      u32_t homingSpeedInputHz;
      memcpy(&homingSpeedInputHz, message + 1, 4);
      homingSpeedHz = min(globalSpeedLimitHz, homingSpeedInputHz);
      break;
    }

    case SET_HOMING_TRIGGER: {
      float homingTriggerInput;
      memcpy(&homingTriggerInput, message + 1, 4);
      powerAvgRangeMultiplier = constrain(homingTriggerInput, 0.1, 10) ;
      preferences.putFloat("homing_trigger", powerAvgRangeMultiplier);
      break;
    }

    case SMOOTH_MOVE: {
      if (messageLength != 10)
        break;
      memcpy(&smoothMoveCommand, message + 1, 9);
      short constrainedPosition = constrain(smoothMoveCommand.depth, 0, 10000);
      smoothMoveCommand.targetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
      smoothMoveCommand.endTimeMs = constrain(smoothMoveCommand.endTimeMs, 20, 3600000);
      smoothMoveCommand.durationReciprocal = 1.0 / smoothMoveCommand.endTimeMs;
      smoothMoveCommand.baseSpeedHz = getMoveBaseSpeedHz(smoothMoveCommand, smoothMoveCommand.endTimeMs);
      smoothMoveStartTime = millis();
      smoothMoveActive = true;
      movementMode = MODE_SMOOTH_MOVE;
      break;
    }
  }
}

static void websocket_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data) {
  esp_websocket_event_data_t *data = (esp_websocket_event_data_t *)event_data;
  switch (event_id) {
    case WEBSOCKET_EVENT_CONNECTED:
      Serial.println("Connected to WebSocket Server");
      setLEDStatus(LED_CONNECTED);  // Update LED status
      sendResponse(CONNECTION);
      break;
    case WEBSOCKET_EVENT_DISCONNECTED:
      Serial.println("Disconnected from WebSocket Server");
      setLEDStatus(LED_ERROR);  // Update LED status
      break;
    case WEBSOCKET_EVENT_DATA:
      parseMessage(data);
      break;
  }
}

void setup() {
  Serial.begin(115200);
  Serial.flush();

  initializeConfiguration();
  checkForConfigMode();
  
  connectToWiFi();
  delay(1000);
  
  // Initialize MQTT
  setupMQTT();
  
  // Initialize WebSocket (existing functionality)
  connectToWebSocketServer();
  esp_websocket_register_events(wsClient, WEBSOCKET_EVENT_ANY, websocket_event_handler, (void *)wsClient);

  initializeMotor();

  Serial.println("");
  Serial.println("");
  Serial.println(" _____  ___  ___  __  __          ");
  Serial.println("(  _  )/ __)/ __)(  \\/  )        ");
  Serial.println(" )(_)( \\__ \\\\__ \\ )    (      ");
  Serial.println("(_____)(___/(___/(_/\\/\\_)  ____ ");
  Serial.println("/ __)  /__\\  (  )(  )/ __)( ___) ");
  Serial.println("\\__ \\ /(__)\\  )(__)(( (__  )__)");
  Serial.println("(___/(__)(__)(______)\\___)(____) ");
  Serial.println(" Firmware v1.4.3 + MQTT");
  Serial.println("");

  moveQueue = xQueueCreate(moveQueueSize, 9);
  positionQueue = xQueueCreate(positionQueueSize, 4);

  sensorlessHoming();

  stepper->setAcceleration(globalAcceleration);
  
  delay(400);

  Serial.println("-- OSSM Ready with MQTT! --");
  sendResponse(CONNECTION);
}

void loop() {
  updateLED();

  // Handle MQTT connection and messages
  if (!mqttClient.connected()) {
    mqttReconnect();
  } else {
    mqttClient.loop();
  }

  switch (movementMode) {
    case MODE_MOVE: {
      playTimeMs = millis() - playStartTime;
      if (playTimeMs >= activeMove.endTimeMs)
        moveStart();
      else if (activeMove.active)
        processStroke(&activeMove, playTimeMs - activeMove.playTimeStartedMs);
      break;
    }

    case MODE_LOOP: {
      playTimeMs = millis() - playStartTime;
      StrokeCommand* loopPhase = (activeLoopPhase == PUSH) ? &loopPush : &loopPull;
      if (playTimeMs <= loopPhase->endTimeMs) {
        processStroke(loopPhase, playTimeMs);
      }
      else {
        activeLoopPhase = (activeLoopPhase == PUSH) ? PULL : PUSH;
        playStartTime = millis();
      }
      break;
    }

    case MODE_VIBRATE: {
      unsigned long currentMs = millis();
      if (currentMs - vibration.currentMs >= vibration.halfPeriodMs) {
        vibration.currentMs = currentMs;
        vibration.direction = (vibration.direction == IN) ? OUT : IN;
        stepper->moveTo((vibration.direction == IN) ? vibration.origin : vibration.crest);
      }
      if (vibration.timed && currentMs >= vibration.endMs) {
        movementMode = MODE_IDLE;
      }
      break;
    }

    case MODE_HOMING: {
      if (stepper->getCurrentPosition() == homingTargetPosition) {
        movementMode = MODE_IDLE;
        sendResponse(HOMING);
      } else {
        stepper->setSpeedInHz(min(homingSpeedHz, globalSpeedLimitHz));
        stepper->moveTo(homingTargetPosition);
      }
      break;
    }

    case MODE_SMOOTH_MOVE: {
      if (smoothMoveActive) {
        unsigned long elapsed = millis() - smoothMoveStartTime;
        if (elapsed >= smoothMoveCommand.endTimeMs) {
          smoothMoveActive = false;
          movementMode = MODE_IDLE;
          sendResponse(SMOOTH_MOVE);
        } else {
          processStroke(&smoothMoveCommand, elapsed);
        }
      }
      break;
    }

  }
  
  delay(1);
}