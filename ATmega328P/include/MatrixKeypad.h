#pragma once
#include <Arduino.h>
#include "Config.h"

class MatrixKeypad {
public:
    void begin(uint32_t nowUs) {
        row_=0; bitmap_=0; candidate_=0; frames_=0; armed_=true; lastScan_=nowUs;
        for(uint8_t i=0;i<4;++i) {
            digitalWrite(Config::ROW_PINS[i],LOW);
            pinMode(Config::ROW_PINS[i],INPUT); // inactive rows are high impedance
            pinMode(Config::COL_PINS[i],INPUT_PULLUP);
        }
        pinMode(Config::ROW_PINS[0],OUTPUT);
    }
    char poll(uint32_t nowUs) {
        if(uint32_t(nowUs-lastScan_)<Config::SCAN_ROW_US) return 0;
        lastScan_=nowUs;
        uint8_t bits=0;
        for(uint8_t c=0;c<4;++c)
            if(digitalRead(Config::COL_PINS[c])==LOW) bits|=uint8_t(1U<<c);
        const uint8_t shift=row_*4;
        bitmap_=(bitmap_ & ~(uint16_t(15U)<<shift)) | (uint16_t(bits)<<shift);
        pinMode(Config::ROW_PINS[row_],INPUT);
        row_=(row_+1)&3;
        // LOW was latched in begin(), so setting OUTPUT never drives HIGH.
        pinMode(Config::ROW_PINS[row_],OUTPUT);
        if(row_!=0) return 0;
        if(bitmap_!=candidate_) { candidate_=bitmap_;frames_=1; }
        else if(frames_<255) ++frames_;
        const uint8_t required=candidate_==0 ? Config::RELEASE_FRAMES : Config::PRESS_FRAMES;
        if(frames_<required) return 0;
        if(candidate_==0) { armed_=true;return 0; }
        if(!armed_) return 0;
        armed_=false;
        // Reject overlapping keys/ghost combinations until stable full release.
        if((candidate_ & (candidate_-1))!=0) return 0;
        static const char keys[16]={'1','2','3','*','4','5','6','D','7','8','9','B','C','0','#','A'};
        for(uint8_t bit=0;bit<16;++bit)
            if(candidate_==uint16_t(1U<<bit)) return keys[bit];
        return 0;
    }
private:
    uint32_t lastScan_;
    uint16_t bitmap_,candidate_;
    uint8_t row_,frames_;
    bool armed_;
};
