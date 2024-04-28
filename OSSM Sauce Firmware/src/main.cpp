#include <Arduino.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "MotorMovement.h"
#include "Network.h"

unsigned long playStartTime;
unsigned long stopTime;
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
  short lastPositionInput = activeMove.positionInput;
  if (!xQueueReceive(moveQueue, &activeMove, (TickType_t)10))
    Serial.println("ERROR: Queue empty.");
  if (activeMove.timingMs == 0 && uxQueueSpacesAvailable(moveQueue) < moveQueueSize) { // start of next path
    playTimeMs = 0;
    playStartTime = millis();
  } else if (activeMove.timingMs == 0 || activeMove.positionInput == lastPositionInput)
    return;
  short constrainedPosition = constrain(activeMove.positionInput, 0, 10000);
  activeMove.targetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
  activeMove.playTimeStartedMs = playTimeMs;
  u32_t durationMs = activeMove.timingMs - activeMove.playTimeStartedMs;
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
  client.sendBinary(message, messageSize);
}


void setup() {
  Serial.begin(115200);
  Serial.flush();

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
  Serial.println(" Firmware v1.1");
  Serial.println("");
  connectToWiFi();
  connectToWebSocketServer();

  moveQueue = xQueueCreate(moveQueueSize, 9);
  positionQueue = xQueueCreate(positionQueueSize, 4);

  sensorlessHoming();
  delay(400);
  Serial.println("-- OSSM Ready! --");
  sendResponse(CONNECTION);

  // On websocket message received
  client.onMessage([&](WebsocketsMessage message) {
    if (movementMode == MODE_HOMING)
      return;
    CommandType commandType = static_cast<CommandType>(message.rawData()[0]);
    switch (commandType) {
      case RESPONSE:
        break;

      case MOVE:
        if (message.length() != 10)
          break;

        if(!xQueueSend(moveQueue, &(message.rawData().c_str()[1]), (TickType_t)10))
          Serial.println("ERROR: Failed to add move command to queue. Is queue full?");
        
        struct {
          uint32_t timingMs;
          short positionInput;
          TransType transType;
          EaseType easeType;
          byte auxiliary;
          long targetPosition;
          uint32_t playTimeStartedMs;
          float durationReciprocal;
          uint32_t baseSpeedHz;
          bool active;
        } sample;
        memcpy(&sample, message.rawData().c_str() + 1, 9);

        if (moveQueueIsEmpty)
          moveStart();
        moveQueueIsEmpty = false;
        break;

      case LOOP:
        if (message.length() != 19)
          break;
        memcpy(&loopPush, message.rawData().c_str() + 1, 9);
        memcpy(&loopPull, message.rawData().c_str() + 10, 9);
        if (loopPush.timingMs != 0) {
          loopPush.targetPosition = rangeLimitUserMax;
          loopPush.durationReciprocal = 1.0 / loopPush.timingMs;
          loopPush.baseSpeedHz = getMoveBaseSpeedHz(loopPush, loopPush.timingMs, true);
        }
        if (loopPull.timingMs != 0) {
          loopPull.targetPosition = rangeLimitUserMin;
          loopPull.durationReciprocal = 1.0 / loopPull.timingMs;
          loopPull.baseSpeedHz = getMoveBaseSpeedHz(loopPull, loopPull.timingMs, true);
        }
        break;

      case POSITION: {
        if (movementMode != MODE_POSITION)
          break;
        u32_t inputPosition;
        memcpy(&inputPosition, message.rawData().c_str() + 1, 4);
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
        Serial.println(movementMode);
        processSafeAccel();
        break;
      }

      case PLAY:
        memcpy(&movementMode, message.rawData().c_str() + 1, 1);
        if (message.length() == 6)
          memcpy(&playTimeMs, message.rawData().c_str() + 2, 4);
        playStartTime = millis() - playTimeMs;
        Serial.print("");
        break;

      case PAUSE:
        movementMode = MODE_IDLE;
        break;

      case RESET:
        movementMode = MODE_IDLE;
        playTimeMs = 0;
        xQueueReset(moveQueue);
        xQueueReset(positionQueue);
        moveQueueIsEmpty = true;
        break;

      case HOMING: {
        u32_t inputPosition;
        memcpy(&inputPosition, message.rawData().c_str() + 1, 4);
        int constrainedPosition = constrain(inputPosition, 0, 10000);
        homingTargetPosition = map(constrainedPosition, 0, 10000, rangeLimitUserMin, rangeLimitUserMax);
        Serial.println(homingTargetPosition);
        movementMode = MODE_HOMING;
        break;
      }

      case CONNECTION:
        sendResponse(CONNECTION);
        break;

      case SET_SPEED_LIMIT: {
        int speedLimit;
        memcpy(&speedLimit, message.rawData().c_str() + 1, 4);
        globalSpeedLimitHz = max(speedLimit, 0);
        break;
      }

      case SET_GLOBAL_ACCELERATION: {
        int acceleration;
        memcpy(&acceleration, message.rawData().c_str() + 1, 4);
        globalAcceleration = max(acceleration, 0);
        break;
      }

      case SET_RANGE_LIMIT: {
        short rangeLimitInput;
        memcpy(&rangeLimitInput, message.rawData().c_str() + 2, 2);
        rangeLimitInput = constrain(rangeLimitInput, 0, 10000);
        rangeLimitInput = map(rangeLimitInput, 0, 10000, rangeLimitHardMin, rangeLimitHardMax);
        byte selectedRange = message.rawData()[1];
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
          if (loopPush.timingMs != 0) {
            loopPush.targetPosition = rangeLimitUserMax;
            loopPush.baseSpeedHz = getMoveBaseSpeedHz(loopPush, loopPush.timingMs, true);
          }
          if (loopPull.timingMs != 0) {
            loopPull.targetPosition = rangeLimitUserMin;
            loopPull.baseSpeedHz = getMoveBaseSpeedHz(loopPull, loopPull.timingMs, true);
          }
        }
        break;
      }

      case SET_HOMING_SPEED: {
        u32_t homingSpeedInputHz;
        memcpy(&homingSpeedInputHz, message.rawData().c_str() + 1, 4);
        homingSpeedHz = min(globalSpeedLimitHz, homingSpeedInputHz);
        break;
      }
    }
  });
}

void loop() {
  if (client.available())
    client.poll();
  
  switch (movementMode) {
    case MODE_MOVE:
      playTimeMs = millis() - playStartTime;
      if (playTimeMs >= activeMove.timingMs)
        moveStart();
      else if (activeMove.active)
        processStroke(&activeMove, playTimeMs - activeMove.playTimeStartedMs);
      break;

    case MODE_LOOP: {
      playTimeMs = millis() - playStartTime;
      StrokeCommand* loopPhase = (activeLoopPhase == PUSH) ? &loopPush : &loopPull;
      if (playTimeMs <= loopPhase->timingMs)
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
