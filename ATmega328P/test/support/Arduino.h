#pragma once
#include <stdint.h>
enum { LOW=0,HIGH=1,INPUT=0,OUTPUT=1,INPUT_PULLUP=2 };
enum { A0=14,A1=15,A2=16,A3=17,A4=18,A5=19 };
void pinMode(uint8_t,uint8_t);
void digitalWrite(uint8_t,uint8_t);
int digitalRead(uint8_t);
