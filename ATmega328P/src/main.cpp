#include <Arduino.h>
#include <LiquidCrystal.h>
#include "Config.h"
#include "DoorLockApp.h"
#include "MatrixKeypad.h"

static DoorLockApp app;
static MatrixKeypad keypad;
static LiquidCrystal lcd(Config::LCD_RS,Config::LCD_E,Config::LCD_D4,
                         Config::LCD_D5,Config::LCD_D6,Config::LCD_D7);
static char desired[2][17],shown[2][16];
static uint32_t lastFrame=0,lastLcdWrite=0,unlockSince=0,errorSince=0;
static bool unlockPulse=false,errorPulse=false;

static void buzzerWrite(bool on) {
    digitalWrite(Config::BUZZER,(on != Config::BUZZER_ACTIVE_LOW)?HIGH:LOW);
}
static void outputTask(uint32_t now) {
    const uint8_t events=app.takeEvents();
    if(events & DoorLockApp::UnlockEvent) { unlockSince=now;unlockPulse=true; }
    if(events & DoorLockApp::ErrorEvent) { errorSince=now;errorPulse=true; }
    if(unlockPulse && uint32_t(now-unlockSince)>=Config::STATUS_PULSE_MS) unlockPulse=false;
    if(errorPulse && uint32_t(now-errorSince)>=Config::STATUS_PULSE_MS) errorPulse=false;
    digitalWrite(Config::UNLOCK_EVENT,unlockPulse?HIGH:LOW);
    digitalWrite(Config::ERROR_EVENT,errorPulse?HIGH:LOW);
    digitalWrite(Config::LOCKED_STATUS,app.locked()?HIGH:LOW);
    buzzerWrite(app.bellOn(now));
}
static void lcdTask(uint32_t now,uint32_t nowUs) {
    if(uint32_t(now-lastFrame)>=20) {
        lastFrame=now;app.render(now,desired[0],desired[1]);
    }
    if(uint32_t(nowUs-lastLcdWrite)<500) return;
    // At most one changed character per loop; never rewrite/clear a whole frame.
    for(uint8_t row=0;row<2;++row) for(uint8_t col=0;col<16;++col) {
        if(shown[row][col]!=desired[row][col]) {
            lcd.setCursor(col,row);
            lcd.write(uint8_t(desired[row][col]));
            shown[row][col]=desired[row][col];lastLcdWrite=nowUs;
            return;
        }
    }
}
void setup() {
    // Latch safe levels before switching GPIO to output mode.
    buzzerWrite(false);pinMode(Config::BUZZER,OUTPUT);
    digitalWrite(Config::UNLOCK_EVENT,LOW);pinMode(Config::UNLOCK_EVENT,OUTPUT);
    digitalWrite(Config::ERROR_EVENT,LOW);pinMode(Config::ERROR_EVENT,OUTPUT);
    digitalWrite(Config::LOCKED_STATUS,LOW);pinMode(Config::LOCKED_STATUS,OUTPUT);
    lcd.begin(16,2);lcd.noCursor();lcd.noBlink();
    app.reset(millis());keypad.begin(micros());
    app.render(millis(),desired[0],desired[1]);
    memset(shown,0,sizeof(shown));
}
void loop() {
    const uint32_t now=millis();
    app.tick(now);
    const char key=keypad.poll(micros());
    if(key) app.handleKey(key,now);
    outputTask(now);
    lcdTask(now,micros());
}
