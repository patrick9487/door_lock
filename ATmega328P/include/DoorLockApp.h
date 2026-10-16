#pragma once
#include <stdint.h>
#include <string.h>

// Hardware-independent controller. Fixed-size storage, no heap allocation.
class DoorLockApp {
public:
    static const uint8_t MaxPasswords=4, MinDigits=6, MaxDigits=128;
    enum Screen : uint8_t { Entry, Checking, Result, Locked, Menu, Change, Add };
    enum Event : uint8_t { UnlockEvent=1, ErrorEvent=2 };

    DoorLockApp() { reset(0); }
    void reset(uint32_t now) {
        memset(passwords_,0,sizeof(passwords_));
        memset(lengths_,0,sizeof(lengths_));
        memcpy(passwords_[0],"123456",6);
        lengths_[0]=6; count_=1; selected_=0; saveSlot_=0; failures_=0;
        brief_=false; reveal_=false; resultSuccess_=false;
        bellActive_=false; bellSince_=now; events_=0;
        clearInput(); setScreen(Entry,now);
    }

    void tick(uint32_t now) {
        if (bellActive_ && elapsed(now,bellSince_)>=550) bellActive_=false;
        if (screen_==Checking && elapsed(now,screenSince_)>=100) {
            bool matched=false;
            for(uint8_t slot=0;slot<count_;++slot)
                if(lengths_[slot]==inputLength_ &&
                   memcmp(passwords_[slot],input_,inputLength_)==0) matched=true;
            clearInput();
            if(matched) {
                failures_=0; resultSuccess_=true; events_|=UnlockEvent;
                setScreen(Result,now);
            } else {
                ++failures_; events_|=ErrorEvent; resultSuccess_=false;
                setScreen(failures_>=3 ? Locked : Result,now);
            }
        } else if(screen_==Result && elapsed(now,screenSince_)>=2000) {
            clearInput(); setScreen(Entry,now);
        } else if(screen_==Locked && elapsed(now,screenSince_)>=30000) {
            failures_=0; clearInput(); setScreen(Entry,now);
        }
    }

    void handleKey(char key,uint32_t now) {
        if(key=='C') {
            if(!bellActive_ || elapsed(now,bellSince_)>=550) {
                bellActive_=true; bellSince_=now;
            }
            return;
        }
        if(screen_==Menu) {
            if(key=='4') {
                if(selected_>0) --selected_;
                screenSince_=now;
            } else if(key=='6') {
                if(selected_+1<count_) { ++selected_; screenSince_=now; }
                else if(count_<MaxPasswords) {
                    saveSlot_=count_; clearInput(); setScreen(Add,now);
                } else screenSince_=now;
            } else if(key=='#') {
                saveSlot_=selected_; clearInput(); setScreen(Change,now);
            } else if(key=='D') { clearInput(); setScreen(Entry,now); }
            return;
        }
        if(screen_!=Entry && screen_!=Change && screen_!=Add) return;
        if(key>='0' && key<='9') {
            if(inputLength_<MaxDigits) {
                input_[inputLength_++]=key;
                reveal_=brief_; revealSince_=now;
            }
        } else if(key=='*') {
            if(inputLength_>0) input_[--inputLength_]=0;
            reveal_=false;
        } else if(key=='B') { brief_=!brief_; reveal_=false; }
        else if(key=='D') {
            clearInput();
            if(screen_!=Entry) setScreen(Menu,now);
        } else if(key=='A' && screen_==Entry) {
            selected_=0; clearInput(); setScreen(Menu,now);
        } else if(key=='#') {
            reveal_=false;
            if(inputLength_<MinDigits) { events_|=ErrorEvent; return; }
            if(screen_==Entry) setScreen(Checking,now);
            else {
                memcpy(passwords_[saveSlot_],input_,inputLength_);
                lengths_[saveSlot_]=inputLength_;
                if(saveSlot_==count_) ++count_;
                selected_=saveSlot_; clearInput(); setScreen(Menu,now);
            }
        }
    }

    void render(uint32_t now,char first[17],char second[17]) const {
        blank(first); blank(second);
        switch(screen_) {
            case Entry: text(first,"ENTER PASSWORD"); break;
            case Checking: text(first,"CHECKING..."); break;
            case Result: text(first,resultSuccess_?"UNLOCKED":"WRONG PASSWORD"); break;
            case Locked: text(first,"LOCKED"); break;
            case Menu:
                text(first,"Change/Add (1/1)");
                first[12]=char('1'+selected_); first[14]=char('0'+count_);
                if((elapsed(now,screenSince_)/3000)%2) text(second,"<4Press Enter 6>");
                else { text(second,"<4 Password 1 6>");second[12]=char('1'+selected_); }
                return;
            case Change:
            case Add: {
                const uint8_t phase=uint8_t((elapsed(now,screenSince_)/3000)%3);
                if(phase==1) text(first,"Enter to Save");
                else if(phase==2) text(first,"Delete to Back");
                else text(first,screen_==Change?"Change Password":"Add Password");
                break;
            }
        }
        if(screen_==Entry || screen_==Change || screen_==Add) {
            const uint8_t start=inputLength_>16 ? inputLength_-16 : 0;
            for(uint8_t i=0;i<16 && uint16_t(start)+i<inputLength_;++i) {
                const uint8_t address=start+i;
                const bool visible=brief_ && reveal_ && elapsed(now,revealSince_)<800
                                   && address==inputLength_-1;
                second[i]=visible ? input_[address] : '*';
            }
        }
    }

    bool bellOn(uint32_t now) const {
        const uint32_t t=elapsed(now,bellSince_);
        return bellActive_ && (t<200 || (t>=350 && t<550));
    }
    uint8_t takeEvents() { const uint8_t value=events_;events_=0;return value; }
    Screen screen() const { return screen_; }
    bool locked() const { return screen_==Locked; }
    uint8_t passwordCount() const { return count_; }
    uint8_t selectedPassword() const { return selected_; }
    uint8_t inputLength() const { return inputLength_; }
    uint8_t failureCount() const { return failures_; }

private:
    char passwords_[MaxPasswords][MaxDigits];
    char input_[MaxDigits];
    uint8_t lengths_[MaxPasswords];
    uint8_t count_,selected_,saveSlot_,failures_,inputLength_,events_;
    Screen screen_;
    bool brief_,reveal_,resultSuccess_,bellActive_;
    uint32_t screenSince_,revealSince_,bellSince_;
    static uint32_t elapsed(uint32_t now,uint32_t since) { return now-since; }
    static void blank(char line[17]) { memset(line,' ',16);line[16]=0; }
    static void text(char line[17],const char* value) {
        for(uint8_t i=0;i<16 && value[i];++i) line[i]=value[i];
    }
    void clearInput() { memset(input_,0,sizeof(input_));inputLength_=0;reveal_=false; }
    void setScreen(Screen screen,uint32_t now) { screen_=screen;screenSince_=now;reveal_=false; }
};
