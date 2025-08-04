#include <Arduino.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "MotorMovement.h"
#include "Configuration.h"

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
  Serial.println(" Firmware v1.4.2");
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

  updateLED();

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