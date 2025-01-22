#ifndef MOTOR_MOVEMENT_H
#define MOTOR_MOVEMENT_H

#include "FastAccelStepper.h"

extern FastAccelStepper *stepper;

extern int rangeLimitHardMin;
extern int rangeLimitHardMax;

extern int rangeLimitUserMin;
extern int rangeLimitUserMax;

extern uint32_t globalSpeedLimitHz;
extern uint32_t globalAcceleration;

extern int homingTargetPosition;
extern uint32_t homingSpeedHz;

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

extern enum LoopPhase {PUSH, PULL} activeLoopPhase;

void initializeMotor();

void sensorlessHoming();

uint32_t getMoveBaseSpeedHz(StrokeCommand stroke, uint32_t moveDuration, bool useFullUserRange = false);

void processSafeAccel();

void processStroke(StrokeCommand* stroke, uint32_t elapsedTimeMs);

#endif
