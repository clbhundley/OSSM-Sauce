#include <Arduino.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "MotorMovement.h"
#include "Network.h"

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

enum CommandType:byte {
  RESPONSE,
  MOVE,
  LOOP,
  POSITION,
  PLAY,
  PAUSE,
  RESET,
  HOMING,
  CONNECTION,
  SET_SPEED_LIMIT,
  SET_GLOBAL_ACCELERATION,
  SET_RANGE_LIMIT,
  SET_HOMING_SPEED,
};

struct Response {
  CommandType commandType = RESPONSE;
  CommandType responseType;
};


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
  esp_websocket_client_send_bin(wsClient, message, messageSize, portMAX_DELAY);
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
        loopPush.targetPosition = rangeLimitUserMax;
        loopPush.durationReciprocal = 1.0 / loopPush.endTimeMs;
        loopPush.baseSpeedHz = getMoveBaseSpeedHz(loopPush, loopPush.endTimeMs, true);
      }
      if (loopPull.endTimeMs != 0) {
        loopPull.targetPosition = rangeLimitUserMin;
        loopPull.durationReciprocal = 1.0 / loopPull.endTimeMs;
        loopPull.baseSpeedHz = getMoveBaseSpeedHz(loopPull, loopPull.endTimeMs, true);
      }
      break;
    }

    case POSITION: {
      if (movementMode != MODE_POSITION)
        break;
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

    case PLAY: {
      memcpy(&movementMode, message + 1, 1);
      if (messageLength == 6)
        memcpy(&playTimeMs, message + 2, 4);
      playStartTime = millis() - playTimeMs;
      Serial.print("");
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
  }
}


static void websocket_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data) {
  esp_websocket_event_data_t *data = (esp_websocket_event_data_t *)event_data;
  switch (event_id) {
    case WEBSOCKET_EVENT_CONNECTED:
      Serial.println("WebSocket Connected");
      break;
    case WEBSOCKET_EVENT_DISCONNECTED:
      Serial.println("WebSocket Disconnected");
      break;
    case WEBSOCKET_EVENT_DATA:
      parseMessage(data);
      break;
  }
}


String getWebSocketAddress() {
   Serial.println("");
   Serial.println("Enter WebSocket server address:");
   while (!Serial.available()) {
      delay(100); // Wait for user input
   }
   String wsServerAddress = Serial.readString();
   wsServerAddress.trim();
   preferences.putString("ws_server", wsServerAddress);
   return wsServerAddress;
}


String constructAddress() {
  String serverAddress;
  serverAddress += "ws://";
  if (preferences.isKey("ws_server"))
    serverAddress += preferences.getString("ws_server");
  else
    serverAddress += getWebSocketAddress();
  serverAddress += ":120";
  return serverAddress;
}


void connectToServer() {
  String serverAddress = constructAddress();
  wsConfig = {.uri = serverAddress.c_str()};
  wsClient = esp_websocket_client_init(&wsConfig);

  if (wsClient) {
    Serial.println("Client initialized");
  } else {
    Serial.println("Failed to initialize client");
  }

  esp_websocket_register_events(wsClient, WEBSOCKET_EVENT_ANY, websocket_event_handler, (void *)wsClient);
  esp_websocket_client_start(wsClient);

  delay(1000);

  if (esp_websocket_client_is_connected(wsClient)) {
      Serial.println("WebSocket client started and connected");
      esp_websocket_client_send_text(wsClient, "Hello WebSocket", strlen("Hello WebSocket"), portMAX_DELAY);
  } else {
      Serial.println("Failed to start WebSocket client or connect");
  }
}


void setup() {
  Serial.begin(115200);
  Serial.flush();

  connectToWiFi();
  
  delay(1000);

  connectToServer();

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
  Serial.println(" Firmware v1.2");
  Serial.println("");

  moveQueue = xQueueCreate(moveQueueSize, 9);
  positionQueue = xQueueCreate(positionQueueSize, 4);

  sensorlessHoming();

  stepper->setAcceleration(globalAcceleration);
  
  delay(400);

  Serial.println("-- OSSM Ready! --");
  sendResponse(CONNECTION);
}


void loop() {
  //if (client.available())
    //client.poll();
  
  switch (movementMode) {
    case MODE_MOVE:
      playTimeMs = millis() - playStartTime;
      if (playTimeMs >= activeMove.endTimeMs)
        moveStart();
      else if (activeMove.active)
        processStroke(&activeMove, playTimeMs - activeMove.playTimeStartedMs);
      break;

    case MODE_LOOP: {
      playTimeMs = millis() - playStartTime;
      StrokeCommand* loopPhase = (activeLoopPhase == PUSH) ? &loopPush : &loopPull;
      if (playTimeMs <= loopPhase->endTimeMs)
        processStroke(loopPhase, playTimeMs);
      else {
        activeLoopPhase = (activeLoopPhase == PUSH) ? PULL : PUSH;
        playStartTime = millis();
      }
      break;
    }

    case MODE_HOMING:
      if (stepper->getCurrentPosition() == homingTargetPosition) {
        movementMode = MODE_IDLE;
        sendResponse(HOMING);
      } else {
        stepper->setSpeedInHz(min(homingSpeedHz, globalSpeedLimitHz));
        stepper->moveTo(homingTargetPosition);
      }
      break;
  }
  
  delay(1);
}
