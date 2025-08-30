#ifndef MOTOR_MOVEMENT_H
#define MOTOR_MOVEMENT_H

#include "FastAccelStepper.h"

#define motorDirectionPin 27
#define motorEnablePin 26
#define motorStepPin 14
#define motorStopPin 19
#define limitSwitchPin 12
#define powerSensorPin 36

extern FastAccelStepper *stepper;

extern float powerAvgRangeMultiplier;

extern int rangeLimitHardMin;
extern int rangeLimitHardMax;

extern int rangeLimitUserMin;
extern int rangeLimitUserMax;

extern uint32_t globalSpeedLimitHz;
extern uint32_t globalAcceleration;

extern int homingTargetPosition;
extern uint32_t homingSpeedHz;

extern enum LoopPhase {PUSH, PULL} activeLoopPhase;

enum Direction {IN, OUT};

enum TransType:byte {
  TRANS_LINEAR,
  TRANS_SINE,
  TRANS_CIRC,
  TRANS_EXPO,
  TRANS_QUAD,
  TRANS_CUBIC,
  TRANS_QUART,
  TRANS_QUINT
};

enum EaseType:byte {
  EASE_IN,
  EASE_OUT,
  EASE_IN_OUT,
  EASE_OUT_IN
};

extern enum MovementMode:byte {
  MODE_IDLE,
  MODE_HOMING,
  MODE_MOVE,
  MODE_POSITION,
  MODE_LOOP,
  MODE_VIBRATE,
  MODE_SMOOTH_MOVE,
} movementMode;

struct StrokeCommand {
  uint32_t endTimeMs;
  short depth;
  TransType transType;
  EaseType easeType;
  byte auxiliary;
  long targetPosition;
  uint32_t playTimeStartedMs;
  float durationReciprocal;
  uint32_t baseSpeedHz;
  bool active;
};

extern struct Vibration {
  int32_t duration;
  uint32_t halfPeriodMs;
  uint16_t position;
  uint8_t rangePercent;
  uint8_t speedScaling;
  int32_t origin;
  int32_t crest;
  Direction direction;
  float movementSpeed;
  bool timed;
  uint32_t endMs;
  uint32_t currentMs;
  int32_t targetPosition;
} vibration;

void initializeMotor();

void sensorlessHoming();

uint32_t getMoveBaseSpeedHz(StrokeCommand stroke, uint32_t moveDuration, bool useFullUserRange = false);

void processSafeAccel();

void processStroke(StrokeCommand* stroke, uint32_t elapsedTimeMs);

#endif
