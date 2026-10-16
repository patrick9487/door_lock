#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "DoorLockApp.h"
#include "MatrixKeypad.h"

static unsigned checks=0;
#define CHECK(test) do { ++checks; if(!(test)) {fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#test);exit(1);} } while(0)
static DoorLockApp app;
static uint32_t now=0;
static void key(char c) { app.handleKey(c,now);++now;app.tick(now); }
static void advance(uint32_t ms) { now+=ms;app.tick(now); }
static void digits(const char* value) { for(;*value;++value) key(*value); }
static void screen(const char* a,const char* b) {
    char first[17],second[17];app.render(now,first,second);
    CHECK(strlen(first)==16 && strlen(second)==16);
    if(strcmp(a,first) || strcmp(b,second)) {
        fprintf(stderr,"Expected [%s]/[%s], got [%s]/[%s]\n",a,b,first,second);
        exit(1);
    }
    ++checks;
}
static void login(const char* password,bool expected) {
    CHECK(app.screen()==DoorLockApp::Entry);
    app.takeEvents();digits(password);key('#');
    CHECK(app.screen()==DoorLockApp::Checking);advance(100);
    const uint8_t events=app.takeEvents();
    CHECK(bool(events & DoorLockApp::UnlockEvent)==expected);
    CHECK(bool(events & DoorLockApp::ErrorEvent)!=expected);
    CHECK(app.screen()==DoorLockApp::Result || app.screen()==DoorLockApp::Locked);
    if(app.screen()==DoorLockApp::Result) advance(2000);
}

static uint8_t modes[20],levels[20];
static uint16_t pressed=0;
void pinMode(uint8_t pin,uint8_t mode) { modes[pin]=mode; }
void digitalWrite(uint8_t pin,uint8_t value) { levels[pin]=value; }
int digitalRead(uint8_t pin) {
    for(uint8_t c=0;c<4;++c) if(pin==Config::COL_PINS[c])
        for(uint8_t r=0;r<4;++r)
            if(modes[Config::ROW_PINS[r]]==OUTPUT && levels[Config::ROW_PINS[r]]==LOW &&
               (pressed & uint16_t(1U<<(r*4+c)))) return LOW;
    return HIGH;
}
static MatrixKeypad keypad;
static uint32_t us=0;
static unsigned events=0;
static char lastKey=0;
static void hold(uint16_t bitmap,unsigned durationMs) {
    pressed=bitmap;
    for(unsigned i=0;i<durationMs;++i) {
        us+=1000;
        const char c=keypad.poll(us);
        if(c) {++events;lastKey=c;}
        unsigned active=0;
        for(uint8_t r=0;r<4;++r) {
            if(modes[Config::ROW_PINS[r]]==OUTPUT) {
                ++active;CHECK(levels[Config::ROW_PINS[r]]==LOW);
            }
        }
        CHECK(active==1);
    }
}

int main() {
    CHECK(sizeof(DoorLockApp)<900);
    app.reset(now);
    screen("ENTER PASSWORD  ","                ");
    digits("12345");key('#');
    CHECK(app.screen()==DoorLockApp::Entry && app.failureCount()==0);
    CHECK(app.takeEvents()==DoorLockApp::ErrorEvent);key('D');
    login("123456",true);
    login("111111",false);login("111111",false);login("111111",false);
    CHECK(app.locked());screen("LOCKED          ","                ");
    key('A');key('1');CHECK(app.locked());
    key('C');CHECK(app.bellOn(now));advance(199);CHECK(!app.bellOn(now));
    advance(150);CHECK(app.bellOn(now));advance(200);CHECK(!app.bellOn(now));
    advance(30000);CHECK(app.screen()==DoorLockApp::Entry);
    puts("PASS: default password, short submit, three-failure lockout, bell during lockout");

    key('A');screen("Change/Add (1/1)","<4 Password 1 6>");
    advance(3000);screen("Change/Add (1/1)","<4Press Enter 6>");
    key('4');CHECK(app.selectedPassword()==0);
    key('#');screen("Change Password ","                ");
    key('9');advance(3000);screen("Enter to Save   ","*               ");
    advance(3000);screen("Delete to Back  ","*               ");
    advance(3000);screen("Change Password ","*               ");
    key('D');key('D');login("123456",true);
    key('A');key('#');digits("654321");key('#');
    screen("Change/Add (1/1)","<4 Password 1 6>");
    key('D');login("123456",false);login("654321",true);
    key('A');key('6');screen("Add Password    ","                ");
    digits("111111");key('D');CHECK(app.passwordCount()==1);
    key('6');digits("222222");key('#');
    screen("Change/Add (2/2)","<4 Password 2 6>");
    key('4');CHECK(app.selectedPassword()==0);key('6');CHECK(app.selectedPassword()==1);
    key('6');digits("333333");key('#');
    key('6');
    for(unsigned i=0;i<128;++i) key('4');
    key('9');CHECK(app.inputLength()==128);key('#');
    screen("Change/Add (4/4)","<4 Password 4 6>");
    key('6');CHECK(app.screen()==DoorLockApp::Menu && app.passwordCount()==4);
    key('D');login("654321",true);login("222222",true);login("333333",true);
    char longPassword[129];memset(longPassword,'4',128);longPassword[128]=0;
    login(longPassword,true);
    key('A');key('6');key('#');digits("000012");key('#');key('D');
    login("222222",false);login("000012",true);login("654321",true);login("333333",true);
    login("888888",false);CHECK(app.failureCount()==1);
    puts("PASS: fixed LCD strings/hints, edit/add/cancel, four-bank capacity, leading zeros, 128 digits");

    app.reset(now);key('B');key('1');screen("ENTER PASSWORD  ","1               ");
    advance(800);screen("ENTER PASSWORD  ","*               ");
    key('*');screen("ENTER PASSWORD  ","                ");
    key('1');key('D');screen("ENTER PASSWORD  ","                ");
    CHECK(app.passwordCount()==1);login("123456",true);
    // All time differences must survive the 32-bit millis/micros rollover.
    now=0xFFFFFFE0U;app.reset(now);key('C');advance(200);CHECK(!app.bellOn(now));
    advance(150);CHECK(app.bellOn(now));advance(200);CHECK(!app.bellOn(now));
    login("123456",true);CHECK(app.screen()==DoorLockApp::Entry);
    puts("PASS: brief reveal, backspace/cancel, volatile reset, clock rollover");

    memset(modes,0,sizeof(modes));memset(levels,0,sizeof(levels));
    us=0xFFFFFF00U;keypad.begin(us);hold(0,40);
    static const char expected[16]={'1','2','3','*','4','5','6','D','7','8','9','B','C','0','#','A'};
    for(unsigned bit=0;bit<16;++bit) {
        const unsigned before=events;
        hold(uint16_t(1U<<bit),100);
        CHECK(events==before+1 && lastKey==expected[bit]);
        hold(uint16_t(1U<<bit),100);CHECK(events==before+1);
        hold(0,20);
    }
    unsigned before=events;
    hold(1,100);hold(0,12);hold(2,100);hold(0,20);
    CHECK(events==before+2 && lastKey=='2');
    before=events;hold(1,4);hold(0,40);CHECK(events==before);
    before=events;hold(3,100);hold(2,100);hold(0,20);CHECK(events==before);
    hold(2,50);hold(0,20);CHECK(events==before+1);
    for(unsigned a=0;a<16;++a) for(unsigned b=a+1;b<16;++b) {
        before=events;hold(uint16_t((1U<<a)|(1U<<b)),40);hold(0,20);
        CHECK(events==before);
    }
    puts("PASS: all 16 physical key positions, held key, short pulse, 12ms release, all two-key pairs, micros rollover");
    printf("ALL PASS: %u checks; controller RAM object = %u bytes\n",checks,unsigned(sizeof(DoorLockApp)));
    return 0;
}
