#pragma once

#include <Arduino.h>
#include <Wire.h>

class DeskTouch {
 public:
  bool begin() {
    instance_ = this;
    pinMode(DESK_TOUCH_INTERRUPT, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(DESK_TOUCH_INTERRUPT), onInterrupt, FALLING);
    if (!Wire.begin(DESK_TOUCH_SDA, DESK_TOUCH_SCL, 400000)) return false;
    Wire.beginTransmission(DESK_TOUCH_ADDRESS);
    controllerPresent_ = Wire.endTransmission() == 0;
    const BaseType_t created = xTaskCreatePinnedToCore(
      taskEntry, "desk-touch", 4096, this, 1, &taskHandle_, 0
    );
    return controllerPresent_ && created == pdPASS;
  }

  bool read(uint16_t &x, uint16_t &y) {
    portENTER_CRITICAL(&mux_);
    if (!pointPending_) {
      portEXIT_CRITICAL(&mux_);
      return false;
    }
    x = pointX_;
    y = pointY_;
    pointPending_ = false;
    portEXIT_CRITICAL(&mux_);
    return true;
  }

  uint32_t touchCount() const { return synchronized(touchCount_); }
  uint32_t interruptCount() const { return synchronized(interruptCount_); }
  uint32_t readErrorCount() const { return synchronized(readErrorCount_); }
  uint32_t pollAttemptCount() const { return synchronized(pollAttemptCount_); }
  uint32_t pollTouchCount() const { return synchronized(pollTouchCount_); }
  bool controllerPresent() const { return synchronized(controllerPresent_); }
  uint32_t lastLatencyMicros() const { return synchronized(lastLatencyMicros_); }
  uint32_t maxLatencyMicros() const { return synchronized(maxLatencyMicros_); }

 private:
  inline static DeskTouch *instance_ = nullptr;
  mutable portMUX_TYPE mux_ = portMUX_INITIALIZER_UNLOCKED;
  TaskHandle_t taskHandle_ = nullptr;
  bool interruptPending_ = false;
  uint32_t pendingAtMicros_ = 0;
  bool pointPending_ = false;
  uint16_t pointX_ = 0;
  uint16_t pointY_ = 0;
  uint32_t touchCount_ = 0;
  uint32_t interruptCount_ = 0;
  uint32_t readErrorCount_ = 0;
  uint32_t pollAttemptCount_ = 0;
  uint32_t pollTouchCount_ = 0;
  uint32_t lastPollAtMs_ = 0;
  bool controllerPresent_ = false;
  uint32_t lastLatencyMicros_ = 0;
  uint32_t maxLatencyMicros_ = 0;

  template <typename T>
  T synchronized(const T &value) const {
    portENTER_CRITICAL(&mux_);
    const T copy = value;
    portEXIT_CRITICAL(&mux_);
    return copy;
  }

  static void taskEntry(void *context) {
    auto *touch = static_cast<DeskTouch *>(context);
    while (true) {
      touch->sample();
      vTaskDelay(pdMS_TO_TICKS(5));
    }
  }

  void sample() {
    const uint32_t nowMs = millis();
    portENTER_CRITICAL(&mux_);
    const bool hadInterrupt = interruptPending_;
    const uint32_t interruptAtMicros = pendingAtMicros_;
    interruptPending_ = false;
    portEXIT_CRITICAL(&mux_);
    const bool shouldProbe = nowMs - lastPollAtMs_ >= DESK_TOUCH_POLL_INTERVAL_MS;
    if (!hadInterrupt && !shouldProbe) return;
    if (!hadInterrupt) {
      lastPollAtMs_ = nowMs;
      portENTER_CRITICAL(&mux_);
      ++pollAttemptCount_;
      portEXIT_CRITICAL(&mux_);
      Wire.beginTransmission(DESK_TOUCH_ADDRESS);
      const bool present = Wire.endTransmission() == 0;
      portENTER_CRITICAL(&mux_);
      controllerPresent_ = present;
      if (!present) ++readErrorCount_;
      portEXIT_CRITICAL(&mux_);
      return;
    }
    // This is the exact command validated by the board's known-good bring-up.
    // Coordinate reads are IRQ-driven; periodic traffic only probes the I2C
    // address so an idle panel cannot manufacture touch samples.
    const uint32_t elapsedSinceInterrupt = micros() - interruptAtMicros;
    if (elapsedSinceInterrupt < DESK_TOUCH_SETTLE_US) {
      delayMicroseconds(DESK_TOUCH_SETTLE_US - elapsedSinceInterrupt);
    }
    static const uint8_t command[8] = {0xB5, 0xAB, 0xA5, 0x5A, 0, 0, 0, 8};
    Wire.beginTransmission(DESK_TOUCH_ADDRESS);
    Wire.write(command, sizeof(command));
    if (Wire.endTransmission() != 0) {
      portENTER_CRITICAL(&mux_);
      controllerPresent_ = false;
      ++readErrorCount_;
      portEXIT_CRITICAL(&mux_);
      return;
    }
    if (Wire.requestFrom(DESK_TOUCH_ADDRESS, 8) != 8) {
      portENTER_CRITICAL(&mux_);
      controllerPresent_ = false;
      ++readErrorCount_;
      portEXIT_CRITICAL(&mux_);
      return;
    }
    uint8_t response[8];
    for (uint8_t &value : response) value = Wire.read();
    const uint32_t sampledAtMicros = micros();
    const uint16_t rawX = (static_cast<uint16_t>(response[2] & 0x0F) << 8) | response[3];
    const uint16_t rawY = (static_cast<uint16_t>(response[4] & 0x0F) << 8) | response[5];
    portENTER_CRITICAL(&mux_);
    controllerPresent_ = true;
    if (!rawX && !rawY) {
      portEXIT_CRITICAL(&mux_);
      return;
    }
    const uint32_t latency = sampledAtMicros - interruptAtMicros;
    lastLatencyMicros_ = latency;
    maxLatencyMicros_ = max(maxLatencyMicros_, latency);
    ++touchCount_;
    pointX_ = min<uint16_t>(DESK_SCREEN_WIDTH - 1, DESK_SCREEN_WIDTH - 1 - rawY);
    pointY_ = min<uint16_t>(DESK_SCREEN_HEIGHT - 1, rawX);
    pointPending_ = true;
    portEXIT_CRITICAL(&mux_);
  }

  static void ARDUINO_ISR_ATTR onInterrupt() {
    if (instance_) {
      portENTER_CRITICAL_ISR(&instance_->mux_);
      ++instance_->interruptCount_;
      instance_->pendingAtMicros_ = micros();
      instance_->interruptPending_ = true;
      portEXIT_CRITICAL_ISR(&instance_->mux_);
    }
  }
};
