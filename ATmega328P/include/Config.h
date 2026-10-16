#pragma once
#include <Arduino.h>

namespace Config {
// Arduino Uno aliases, NOT the old FPGA Pxxx numbers.
static const uint8_t ROW_PINS[4] = {2, 3, 4, 5};
static const uint8_t COL_PINS[4] = {6, 7, 8, 9};
static const uint8_t LCD_RS=10, LCD_E=11;
static const uint8_t LCD_D4=12, LCD_D5=13, LCD_D6=A0, LCD_D7=A1;
static const uint8_t BUZZER=A2;
// A logic-input active buzzer module, inactive HIGH like the FPGA version.
static const bool BUZZER_ACTIVE_LOW=true;
static const uint8_t UNLOCK_EVENT=A3, ERROR_EVENT=A4, LOCKED_STATUS=A5;
static const uint16_t STATUS_PULSE_MS=100;
static const uint16_t SCAN_ROW_US=1000;
static const uint8_t PRESS_FRAMES=5;   // about 20 ms of stable press
static const uint8_t RELEASE_FRAMES=2; // about 8 ms of stable release
}
