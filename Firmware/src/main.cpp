#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <ArduinoWebsockets.h>
#include "FastAccelStepper.h"

#define dirPinStepper 27
#define enablePinStepper 26
#define stepPinStepper 14

FastAccelStepperEngine engine = FastAccelStepperEngine();
FastAccelStepper *stepper = NULL;

using namespace websockets;
WebsocketsClient client;

Preferences preferences;

enum MovementMode {
  MODE_IDLE,
  MODE_HOMING,
  MODE_MOVE,
  MODE_POSITION,
  MODE_LOOP,
  MODE_CYCLE // not currently implemented
};

enum TransType {
  TRANS_LINEAR,
  TRANS_SINE,
  TRANS_CIRC,
  TRANS_EXPO,
  TRANS_QUAD,
  TRANS_CUBIC,
  TRANS_QUART,
  TRANS_QUINT
};

enum EaseType {
  EASE_IN,
  EASE_OUT,
  EASE_IN_OUT,
  EASE_OUT_IN
};

int limitHardMin;
int limitHardMax;

int limitUserMin;
int limitUserMax;

int homingSpeedHz = 1000;

int globalSpeedLimitHz = 20000;
int globalAcceleration = 20000;

MovementMode movementMode = MODE_IDLE;

int moveStartMs;
int moveEndMs;
float moveDurationReciprocal;
int moveTargetPosition;
int moveBaseSpeedHz;
TransType moveTrans;
EaseType moveEase;

int strokeDurationMs;
float strokeDurationReciprocal;
float strokeLinearMoveSpeed;

int strokePushBaseSpeed;
TransType strokePushTrans;
EaseType strokePushEase;

int strokePullBaseSpeed;
TransType strokePullTrans;
EaseType strokePullEase;

int homingTargetPosition;
int lastPositionCommand;

float getAnalogAvgPercent(int pinNumber, int samples) { //From OSSM 'Utilities.cpp'
  float sum = 0;
  float average = 0;
  float percentage = 0;
  for (int i = 0; i < samples; i++) {
    // TODO: Possibly use fancier filters?
    sum += analogRead(pinNumber);
  }
  average = sum / samples;
  // TODO: Might want to add a deadband
  percentage = 100.0 * average / 4096.0; // 12 bit resolution
  return percentage;
}

void sensorlessHoming() {
  Serial.println("");
  Serial.println("Beginning sensorless homing...");
  float currentLimit = 1.5;
  float currentSensorOffset = (getAnalogAvgPercent(36, 1000));
  float current = getAnalogAvgPercent(36, 200) - currentSensorOffset;

  //relax motor
  digitalWrite(enablePinStepper, HIGH);
  delay(600);
  digitalWrite(enablePinStepper, LOW);
  delay(100);

  stepper->setAcceleration(90000);
  stepper->setSpeedInUs(2000);

  //find physical maximum limit
  int limitPhysicalMax;
  stepper->runForward();
  current = getAnalogAvgPercent(36, 200) - currentSensorOffset;
  while (current < currentLimit) {
    current = getAnalogAvgPercent(36, 25) - currentSensorOffset;
  }
  stepper->stopMove();
  limitPhysicalMax = stepper->getCurrentPosition();

  delay(400);

  //find physical minimum limit
  int limitPhysicalMin;
  stepper->runBackward();
  current = getAnalogAvgPercent(36, 200) - currentSensorOffset;
  while (current < currentLimit) {
    current = getAnalogAvgPercent(36, 25) - currentSensorOffset;
  }
  stepper->stopMove();
  limitPhysicalMin = stepper->getCurrentPosition();

  delay(400);

  //set hard limits
  float hardLimitBuffer = abs(limitPhysicalMax - limitPhysicalMin) * 0.06;
  limitHardMin = limitPhysicalMin + hardLimitBuffer;
  limitHardMax = limitPhysicalMax - hardLimitBuffer;

  limitUserMin = limitHardMin;
  limitUserMax = limitHardMax;

  Serial.println("");
  Serial.print("MINIMUM RANGE LIMIT: ");
  Serial.println(limitHardMin);
  Serial.print("MAXIMUM RANGE LIMIT: ");
  Serial.println(limitHardMax);
  Serial.println("");
  Serial.println("TOTAL RANGE: ");
  Serial.println(abs(limitHardMax - limitHardMin));
  Serial.println("");
}

double exponentEasing(double weight, EaseType easing, int exponent) {
  switch (easing) {
    case EASE_IN:
      return pow(weight, exponent);
    case EASE_OUT:
      return pow(weight - 1, exponent);
    case EASE_IN_OUT:
      return pow((1 - abs(2 * weight - 1)), exponent);
    case EASE_OUT_IN:
      return pow((1 - abs(2 * weight - 1)) - 1, exponent);
  }
  return 0;
}

double interpolate(double weight, TransType transType, EaseType easeType) {
  switch (transType) {
    case TRANS_LINEAR:
      return 1;
    
    case TRANS_SINE:
      switch (easeType) {
        case EASE_IN:
          return 1 - cos(weight * PI * 0.5);
        case EASE_OUT:
          return 1 - sin(weight * PI * 0.5);
        case EASE_IN_OUT:
          return 1 - cos((1 - abs(2 * weight - 1)) * PI * 0.5);
        case EASE_OUT_IN:
          return 1 - sin((1 - abs(2 * weight - 1)) * PI * 0.5);
      }
    
    case TRANS_CIRC:
      switch (easeType) {
        case EASE_IN:
          return 1 - sqrt(1 - pow(weight, 2));
        case EASE_OUT:
          return 1 - sqrt(1 - pow(weight - 1, 2));
        case EASE_IN_OUT:
          return 1 - sqrt(1 - pow((1 - abs(2 * weight - 1)), 2));
        case EASE_OUT_IN:
          return 1 - sqrt(1 - pow((1 - abs(2 * weight - 1)) - 1, 2));
      }
    
    case TRANS_EXPO:
      switch (easeType) {
        case EASE_IN:
          return pow(2, 10 * (weight - 1));
        case EASE_OUT:
          return pow(2, -10 * weight);
        case EASE_IN_OUT:
          return pow(2, 10 * ((1 - abs(2 * weight - 1)) - 1));
        case EASE_OUT_IN:
          return pow(2, -10 * (1 - abs(2 * weight - 1)));
      }

    case TRANS_QUAD:
      return exponentEasing(weight, easeType, 2);
    case TRANS_CUBIC:
      return abs(exponentEasing(weight, easeType, 3));
    case TRANS_QUART:
      return exponentEasing(weight, easeType, 4);
    case TRANS_QUINT:
      return abs(exponentEasing(weight, easeType, 5));
  }
  return 0;
}

//compensating for extra acceleration to match traversal with linear move
float moveSpeedScaling(float linearMoveSpeed, TransType transType) {
  switch (transType) {
    case TRANS_SINE:
      return linearMoveSpeed * 2.73;
    case TRANS_CIRC:
      return linearMoveSpeed * 4.46;
    case TRANS_EXPO:
      return linearMoveSpeed * 6.9;
    case TRANS_QUAD:
      return linearMoveSpeed * 2.98;
    case TRANS_CUBIC:
      return linearMoveSpeed * 3.9;
    case TRANS_QUART:
      return linearMoveSpeed * 4.85;
    case TRANS_QUINT:
      return linearMoveSpeed * 5.79;
    default:
      return linearMoveSpeed;
  }
}

void processMove() {
  int elapsedTime = millis() - moveStartMs;
  double percentage = elapsedTime * moveDurationReciprocal;
  double speedOscillation = interpolate(percentage, moveTrans, moveEase);
  int moveSpeedHz = round(moveBaseSpeedHz * max(speedOscillation, 0.01));
  stepper->setSpeedInHz(min(moveSpeedHz, globalSpeedLimitHz));
  stepper->moveTo(moveTargetPosition);
}

bool push;
float prevCyclePercent;
int32_t prevPosition;
int stepperDirection;
unsigned long loopStartTime;
void processLoop() {
  float cyclePercent = ((millis() - loopStartTime) % strokeDurationMs) * strokeDurationReciprocal;
  if (cyclePercent < prevCyclePercent) {  //CYCLE END
    if (movementMode == MODE_CYCLE && !push) {
      movementMode = MODE_IDLE;
      prevCyclePercent = cyclePercent;
      return;
    }
    push = !push;
  }
  
  int32_t position = stepper->getCurrentPosition();
  if (push) {  //THRUST IN
    if (position >= limitUserMax) {
      loopStartTime = millis();
      prevCyclePercent = 1;
      return;
    }

    if (stepperDirection < 1 && position > prevPosition) { // safely apply changes to global acceleration
      stepperDirection = 1;
      if (stepper->getAcceleration() != globalAcceleration) {
        stepper->forceStop();
        stepper->setAcceleration(globalAcceleration);
      }
    }

    double speedOscillation = interpolate(cyclePercent, strokePushTrans, strokePushEase);
    int moveSpeedHz = round(strokePushBaseSpeed * max(speedOscillation, 0.01));
    stepper->setSpeedInHz(min(moveSpeedHz, globalSpeedLimitHz));
    stepper->moveTo(limitUserMax);

  } else {  //THRUST OUT
    if (position <= limitUserMin) {
      loopStartTime = millis();
      prevCyclePercent = 1;
      return;
    }

    if (stepperDirection > -1 && position < prevPosition) { // safely apply changes to global acceleration
      stepperDirection = -1;
      if (stepper->getAcceleration() != globalAcceleration) {
        stepper->forceStop();
        stepper->setAcceleration(globalAcceleration);
      }
    }

    double speedOscillation = interpolate(cyclePercent, strokePullTrans, strokePullEase);
    int moveSpeedHz = round(strokePullBaseSpeed * max(speedOscillation, 0.01));
    stepper->setSpeedInHz(min(moveSpeedHz, globalSpeedLimitHz));
    stepper->moveTo(limitUserMin);
  }

  prevCyclePercent = cyclePercent;
  prevPosition = position;
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

void setup() {
  Serial.begin(115200);
  Serial.flush();

  WiFi.mode(WIFI_STA);

  //initialize stepper
  engine.init();
  stepper = engine.stepperConnectToPin(stepPinStepper);
  Serial.println("Starting");
  Serial.print("Stepper Pin:");
  Serial.println(stepPinStepper);
  Serial.flush();
  Serial.println((unsigned int)stepper);
  Serial.println((unsigned int)&engine);
  if (stepper) {
    stepper->setDirectionPin(dirPinStepper);
    stepper->setEnablePin(enablePinStepper);
    stepper->setAutoEnable(true);
  } else {
    Serial.println("Stepper Not initialized!");
    delay(1000);
  }
  Serial.print("    F_CPU=");
  Serial.println(F_CPU);
  Serial.print("    TICKS_PER_S=");
  Serial.println(TICKS_PER_S);
  Serial.flush();

  Serial.println("");
  Serial.println("");
  Serial.println(" _____  ___  ___  __  __          ");
  Serial.println("(  _  )/ __)/ __)(  \\/  )        ");
  Serial.println(" )(_)( \\__ \\\\__ \\ )    (      ");
  Serial.println("(_____)(___/(___/(_/\\/\\_)  ____ ");
  Serial.println("/ __)  /__\\  (  )(  )/ __)( ___) ");
  Serial.println("\\__ \\ /(__)\\  )(__)(( (__  )__)");
  Serial.println("(___/(__)(__)(______)\\___)(____) ");
  Serial.println(" Firmware v1.0");
  
  // Connect to WiFi
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

  // Connect to WebSocket server
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
    client.send("OSSM Connected");
    Serial.println("-- Connected to WebSocket server! --");
    Serial.println("");
  } else {
    Serial.println("Failed to connect to WebSocket server!");
    preferences.end();
    ESP.restart();
    delay(1000);
  }

  //on websocket message received
  client.onMessage([&](WebsocketsMessage message) {
    String data = message.data();
    switch (data[0]) {

      case 'M': { //move command
        movementMode = MODE_MOVE;

        int dIndex = data.indexOf('D');
        int tIndex = data.indexOf('T');
        int eIndex = data.indexOf('E');
        int inputPosition = constrain(data.substring(1, dIndex).toInt(), 0, 9999);
        int durationMs = data.substring(dIndex + 1, tIndex).toInt();

        TransType transType = TransType(data.substring(tIndex + 1, eIndex).toInt());
        EaseType easeType = EaseType(data.substring(eIndex + 1).toInt());

        int targetPosition = map(inputPosition, 0, 9999, limitUserMin, limitUserMax);

        // find way to safely apply changes to acceleration at beginning of move
        // instead of force-stopping whenever global acceleration is changed
        /*
        if (stepper->getAcceleration() != globalAcceleration) {
           stepper->forceStop();
          stepper->setAcceleration(globalAcceleration);
          stepper->applySpeedAcceleration();
        }
        */

        if (targetPosition != moveTargetPosition) {
          moveStartMs = millis();
          moveEndMs = moveStartMs + durationMs;
          moveDurationReciprocal = 1.0 / durationMs;
          moveTrans = transType;
          moveEase = easeType;
          moveTargetPosition = constrain(targetPosition, limitUserMin, limitUserMax);
          int moveDelta = moveTargetPosition - stepper->getCurrentPosition();
          moveBaseSpeedHz = moveSpeedScaling(abs(moveDelta / (durationMs * 0.001)), transType);
          processMove();
        }
        break;
      }

      case 'L': { //loop command
        int tIndex1 = data.indexOf('T');
        int eIndex1 = data.indexOf('E');
        int tIndex2 = data.indexOf('T', tIndex1 + 1);
        int eIndex2 = data.indexOf('E', eIndex1 + 1);
        int cycleFlag = data.indexOf('C', eIndex2 + 1);

        TransType inputPushTrans = TransType(data.substring(tIndex1 + 1, eIndex1).toInt());
        EaseType inputPushEase = EaseType(data.substring(eIndex1 + 1, tIndex2).toInt());

        TransType inputPullTrans = TransType(data.substring(tIndex2 + 1, eIndex2).toInt());
        EaseType inputPullEase = EaseType(data.substring(eIndex2 + 1).toInt());

        unsigned long inputDurationMs = data.substring(1, tIndex1).toInt();

        if (!inputDurationMs) { //loop stop command
          stepper->forceStop();
          movementMode = MODE_IDLE;
        } else if (cycleFlag > -1) {
          movementMode = MODE_CYCLE;
        } else {
          movementMode = MODE_LOOP;
        }

        if (movementMode == MODE_CYCLE || inputDurationMs != strokeDurationMs) {
          if (movementMode != MODE_LOOP) {
            push = true;
            loopStartTime = millis();
          }
          strokeDurationMs = inputDurationMs;
          strokeDurationReciprocal = 1.0 / inputDurationMs;
          strokeLinearMoveSpeed = abs((limitUserMax - limitUserMin) / (inputDurationMs * 0.001));
          strokePushBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, inputPushTrans);
          strokePullBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, inputPullTrans);
        }
        if (inputPushTrans != strokePushTrans) {
          strokePushBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, inputPushTrans);
        }
        if (inputPullTrans != strokePullTrans) {
          strokePullBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, inputPullTrans);
        }
        strokePushTrans = inputPushTrans;
        strokePushEase = inputPushEase;
        strokePullTrans = inputPullTrans;
        strokePullEase = inputPullEase;
        prevCyclePercent = 0;
        break;
      }

      case 'P': { //position command
        movementMode = MODE_POSITION;

        int inputCommand = constrain(data.substring(1).toInt(), 0, 9999);
        int inputPosition = map(inputCommand, 0, 9999, limitUserMin, limitUserMax);
        
        int positionDelta = inputPosition - lastPositionCommand;
        int currentPosition = stepper->getCurrentPosition();

        bool lockedMin = inputPosition < currentPosition && positionDelta > 0;
        bool lockedMax = inputPosition > currentPosition && positionDelta < 0;

        lastPositionCommand = inputPosition;

        if (lockedMin || lockedMax)
          return;
        int speed = abs(positionDelta) * 50; // app should send position data in 20ms intervals
        stepper->setSpeedInHz(min(speed, globalSpeedLimitHz));
        stepper->moveTo(inputPosition);
        break;
      }

      case 'H': { //position homing
        if (data.substring(1) == "C") {
          return;
        } else if (data.substring(1, 2) == "S") {
          homingSpeedHz = min(int(data.substring(2).toInt()), globalSpeedLimitHz);
          return;
        }
        movementMode = MODE_HOMING;
        homingTargetPosition = map(data.substring(1).toInt(), 0, 9999, limitUserMin, limitUserMax);
        stepper->setSpeedInHz(min(homingSpeedHz, globalSpeedLimitHz));
        stepper->moveTo(constrain(homingTargetPosition, limitUserMin, limitUserMax));
        break;
      }

      case 'A': { //set minimum range
        int inputPosition = constrain(data.substring(1).toInt(), 0, 9999);
        limitUserMin = map(inputPosition, 0, 9999, limitHardMin, limitHardMax);
        if (movementMode == MODE_LOOP) {
          strokeLinearMoveSpeed = abs((limitUserMax - limitUserMin) / (strokeDurationMs * 0.001));
          strokePushBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, strokePushTrans);
          strokePullBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, strokePullTrans);
        }
        break;
      }

      case 'Z': { //set maximum range
        int inputPosition = constrain(data.substring(1).toInt(), 0, 9999);
        limitUserMax = map(inputPosition, 0, 9999, limitHardMin, limitHardMax);
        if (movementMode == MODE_LOOP) {
          strokeLinearMoveSpeed = abs((limitUserMax - limitUserMin) / (strokeDurationMs * 0.001));
          strokePushBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, strokePushTrans);
          strokePullBaseSpeed = moveSpeedScaling(strokeLinearMoveSpeed, strokePullTrans);
        }
        break;
      }
      
      case 'S': //set global speed limit
        globalSpeedLimitHz = max(int(data.substring(1).toInt()), 0);
        break;
      
      case 'X': //set global acceleration
        globalAcceleration = data.substring(1).toInt();
        if (movementMode == MODE_POSITION || movementMode == MODE_MOVE) {
          stepper->forceStop();
          stepper->setAcceleration(globalAcceleration);
          stepper->applySpeedAcceleration();
        }
        break;

      case 'C': //connection handshake with app
        if (data.substring(1) == ":APP") {
          client.send("C:OSSM");
        }
        break;
    }
  });
  
  sensorlessHoming();

  stepper->setAutoEnable(false);
  digitalWrite(enablePinStepper, LOW);

  stepper->setAcceleration(globalAcceleration);
  stepper->moveTo(limitHardMin);

  delay(1000);
  Serial.println("-- OSSM Ready! --");
  client.send("C:OSSM");
}

void loop() {
  if (client.available()) {
    client.poll();
  }
  switch (movementMode) {
    case MODE_MOVE:
      if (moveEndMs && millis() <= moveEndMs) {
        processMove();
      }
      break;
    case MODE_LOOP:
    case MODE_CYCLE:
      if (strokeDurationMs) {
        processLoop();
      }
      break;
    case MODE_HOMING:
      if (stepper->getCurrentPosition() == homingTargetPosition) {
        movementMode = MODE_IDLE;
        client.send("HC");
      }
  }
  delay(1);
}
