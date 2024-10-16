#include <Arduino.h>
#include "MotorMovement.h"

#define motorDirectionPin 27
#define motorEnablePin 26
#define motorStepPin 14
#define motorStopPin 19
#define limitSwitchPin 12
#define powerSensorPin 36

const int powerAvgRangeMultiplier = 1.5; //raise to decrease, or lower to increase sensitivity of sensorless homing
const int outliersSampleSize = 10;
const int powerSampleSize = 10;
const int deltaSampleLength = 6000;

FastAccelStepperEngine engine = FastAccelStepperEngine();
FastAccelStepper *stepper = NULL;

int rangeLimitHardMin;
int rangeLimitHardMax;

int rangeLimitUserMin;
int rangeLimitUserMax;

uint32_t globalSpeedLimitHz = 20000;
uint32_t globalAcceleration = 20000;
bool applyAcceleration;

MovementMode movementMode;

LoopPhase activeLoopPhase;

int32_t previousStrokePosition;
enum {IN, OUT} movementDirection;

int homingTargetPosition;
uint32_t homingSpeedHz = 1000;


void initializeMotor() {
  engine.init();
  stepper = engine.stepperConnectToPin(motorStepPin);

  Serial.println((unsigned int)stepper);
  Serial.println((unsigned int)&engine);

  if (stepper) {
    stepper->setDirectionPin(motorDirectionPin);
    stepper->setEnablePin(motorEnablePin);
    stepper->setAutoEnable(true);
  } else {
    Serial.println("Stepper Not initialized!");
    delay(1000);
  }

  Serial.print("    F_CPU=");
  Serial.println(F_CPU);
  Serial.print("    TICKS_PER_S=");
  Serial.println(TICKS_PER_S);
}


float powerAvgRange;
float powerEMAFast;
float powerEMASlow;
float powerEMASlowSmooth;
float powerEMASlowDoubleSmooth;
bool powerSpikeTriggered;
float deltaArray[deltaSampleLength];
void getPowerReading(bool takeDeltaSample = false, int deltaSampleIndex = 0) {
  float sum;
  for (int i = 0; i < powerSampleSize; i++)
    sum += analogRead(powerSensorPin);
  float sampleAverage = sum / powerSampleSize;

  powerEMAFast = ((sampleAverage - powerEMAFast) * 0.1) + powerEMAFast;

  powerEMASlow = ((sampleAverage - powerEMASlow) * 0.02) + powerEMASlow;
  powerEMASlowSmooth = ((powerEMASlow - powerEMASlowSmooth) * 0.02) + powerEMASlowSmooth;
  powerEMASlowDoubleSmooth = ((powerEMASlowSmooth - powerEMASlowDoubleSmooth) * 0.01) + powerEMASlowDoubleSmooth;

  if (takeDeltaSample) {
    deltaArray[deltaSampleIndex] = powerEMAFast - powerEMASlowDoubleSmooth;
  }

  if (powerEMAFast > powerEMASlowDoubleSmooth + powerAvgRange) {
    powerSpikeTriggered = true;
  }
}


void sensorlessHoming() {
// root mean square could be a better way to determine averages
  Serial.println("");
  Serial.println("Scanning power consumption variance...");
  Serial.println("");

  powerEMAFast = 0;
  powerEMASlow = 0;
  powerEMASlowSmooth = 0;
  powerEMASlowDoubleSmooth = 0;

  //relax motor
  digitalWrite(motorEnablePin, HIGH);
  delay(600);
  digitalWrite(motorEnablePin, LOW);
  delay(100);

  stepper->setAcceleration(160000);
  stepper->setSpeedInUs(1800);

  //stabilize EMA
  for (int i = 0; i < 1200; i++) {
    getPowerReading();
  }

  //take samples
  for (int i = 0; i < 5000; i++) {
    getPowerReading(true, i);
  }

  //bubble sort samples ascending
  for (int i = 0; i < deltaSampleLength - 1; i++) {
    for (int j = 0; j < deltaSampleLength - i - 1; j++) {
      if (deltaArray[j] > deltaArray[j + 1]) {
        float temp = deltaArray[j];
        deltaArray[j] = deltaArray[j + 1];
        deltaArray[j + 1] = temp;
      }
    }
  }

  //get average of lowest 10 samples
  float outliersAvgLow = 0;
  for (int i = 0; i < outliersSampleSize; i++) {
    outliersAvgLow += deltaArray[i];
  }
  outliersAvgLow = outliersAvgLow / outliersSampleSize;

  //get average of highest 10 samples
  float outliersAvgHigh = 0;
  for (int i = 1; i < outliersSampleSize; i++) {
    outliersAvgHigh += deltaArray[deltaSampleLength - i];
  }
  outliersAvgHigh = outliersAvgHigh / outliersSampleSize;

  //get average range of samples
  powerAvgRange = outliersAvgHigh - outliersAvgLow;
  powerAvgRange *= powerAvgRangeMultiplier;

  Serial.println("");
  Serial.println("Beginning sensorless homing...");
  Serial.println("");

  //find physical maximum limit
  powerEMAFast = powerEMASlowDoubleSmooth;
  powerSpikeTriggered = false;
  int limitPhysicalMax;

  stepper->runForward();
  while (!powerSpikeTriggered) {
    getPowerReading();
  }
  stepper->stopMove();
  limitPhysicalMax = stepper->getCurrentPosition();
  stepper->move(-50);

  delay(300);

  //find physical minimum limit
  powerEMAFast = powerEMASlowDoubleSmooth;
  powerSpikeTriggered = false;
  int limitPhysicalMin;

  stepper->runBackward();
  while (!powerSpikeTriggered) {
    getPowerReading();
  }
  stepper->stopMove();
  limitPhysicalMin = stepper->getCurrentPosition();

  delay(200);

  //lock motor movement
  stepper->setAutoEnable(false);
  digitalWrite(motorEnablePin, LOW);

  stepper->moveTo(rangeLimitHardMin);

  //set hard limits
  float hardLimitBuffer = abs(limitPhysicalMax - limitPhysicalMin) * 0.06;
  rangeLimitHardMin = limitPhysicalMin + hardLimitBuffer;
  rangeLimitHardMax = limitPhysicalMax - hardLimitBuffer;

  rangeLimitUserMin = rangeLimitHardMin;
  rangeLimitUserMax = rangeLimitHardMax;

  Serial.println("");
  Serial.print("MINIMUM RANGE LIMIT: ");
  Serial.println(rangeLimitHardMin);
  Serial.print("MAXIMUM RANGE LIMIT: ");
  Serial.println(rangeLimitHardMax);
  Serial.println("");
  Serial.println("TOTAL RANGE: ");
  Serial.println(abs(rangeLimitHardMax - rangeLimitHardMin));
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
    default:
      return 0;
  }
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
    
    default:
      return 0;
  }
}


//amplifying base move speed to match traversal time with linear move
uint32_t getMoveBaseSpeedHz(StrokeCommand stroke, uint32_t moveDuration, bool useFullUserRange) {
  int moveDelta;
  if (useFullUserRange)
    moveDelta = rangeLimitUserMax - rangeLimitUserMin;
  else
    moveDelta = stroke.targetPosition - stepper->getCurrentPosition();
  float linearMoveSpeed = abs(moveDelta) / (moveDuration * 0.001);
  switch (stroke.transType) {
    case TRANS_SINE:
      return round(linearMoveSpeed * 2.73);
    case TRANS_CIRC:
      return round(linearMoveSpeed * 4.46);
    case TRANS_EXPO:
      return round(linearMoveSpeed * 6.9);
    case TRANS_QUAD:
      return round(linearMoveSpeed * 2.98);
    case TRANS_CUBIC:
      return round(linearMoveSpeed * 3.9);
    case TRANS_QUART:
      return round(linearMoveSpeed * 4.85);
    case TRANS_QUINT:
      return round(linearMoveSpeed * 5.79);
    default:
      return round(linearMoveSpeed);
  }
}


void processSafeAccel() {
  int32_t currentPosition = stepper->getCurrentPosition();
  if (currentPosition < previousStrokePosition) {
    if (movementDirection == OUT)
      applyAcceleration = true;
    movementDirection = IN;
  } else if (currentPosition > previousStrokePosition) {
    if (movementDirection == IN)
      applyAcceleration = true;
    movementDirection = OUT;
  }
  previousStrokePosition = currentPosition;
  if (applyAcceleration) {
    applyAcceleration = false;
    if (stepper->getAcceleration() == globalAcceleration)
      return;
    stepper->forceStop();
    stepper->setAcceleration(globalAcceleration);
    stepper->applySpeedAcceleration();
  }
}


void processStroke(StrokeCommand* stroke, uint32_t elapsedTimeMs) {
  double percentage = elapsedTimeMs * stroke->durationReciprocal;
  double accelerationCurve = interpolate(percentage, stroke->transType, stroke->easeType);
  uint32_t moveSpeedHz = round(stroke->baseSpeedHz * max(accelerationCurve, 0.01));
  stepper->setSpeedInHz(min(moveSpeedHz, globalSpeedLimitHz));
  stepper->moveTo(stroke->targetPosition);
  processSafeAccel();
}
