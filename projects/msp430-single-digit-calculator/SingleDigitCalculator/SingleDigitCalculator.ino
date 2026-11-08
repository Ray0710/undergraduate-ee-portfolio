// Undergraduate firmware archive. Transcribed from the coursework listing.
//Calculator seven-segment display
#define dataPin 11
#define latchPin 12
#define clockPin 13

//The need of debounce in interrupt
int lastButtonState = LOW;
long Debounce1;
long Debounce2;
long Debounce3;
long debounceDelay = 50;

//The constant that will be calaulate
int calcucons1 = 0;
int calcucons2 = 0;
int cycle[]={243,73,97,51,37,7,241,1,49};
int modecycle[] = {243,254,73,254,97,254,51,254};
int cons[] = {243,73,97,51,37,7,241,1,49};
int resultar[] = {129,243,73,97,51,37,7,241,1,49,254};

//Variebles
int temp;
int modetemp;
int mode = 1;
int wayforcalcu;
float result;

//The button of changing mode
#define stepbutton 28 //with interrupt,button
#define resetbutton 30 //button

//129->1000,0001------0 37 ->0010,0101------5
//243->1111,0011------1 7  ->0000,0111------6
//73 ->0100,1001------2 241->1111,0001------7
//97 ->0110,0001------3 1  ->0000,0001------8
//51 ->0011,0011------4 49 ->0011,0001------9
//254->1111,1110------dp

void ISRstep(){//it allow us to change mode to next step
  int reading1 = digitalRead(stepbutton);//spectator the situation of digital of button
  if (reading1 != lastButtonState) {
    Debounce1 = millis();//caculate the time
    lastButtonState = reading1;
    }
    if((millis() -Debounce1) > debounceDelay) {//if the time user pause the button over the set
      mode = mode +1;
      if(mode > 8){//cycle
        mode = 1;
      }
}
}

void ISRreset(){//allow us to restart the way to calculate
  int reading2 = digitalRead(resetbutton);//spectator the situation of digital of button
  if (reading2 != lastButtonState) {
    Debounce2 = millis();//caculate the time
    lastButtonState = reading2;
    }
    if((millis() -Debounce2) > debounceDelay) {//if the time user pause the button over the set
      mode = 1;
}
}

void setup() {
  pinMode(dataPin,OUTPUT);
  pinMode(latchPin,OUTPUT);
  pinMode(clockPin,OUTPUT);
  attachInterrupt(digitalPinToInterrupt(stepbutton),ISRstep,FALLING);
  attachInterrupt(digitalPinToInterrupt(resetbutton),ISRreset,FALLING);
  pinMode(stepbutton,INPUT_PULLUP);
  pinMode(resetbutton,INPUT_PULLUP);
}

 void loop() {
    while(mode == 1){//tip for first step by shiny between the dot and 1
        for(int i = 0;i < 2;i++){
          modetemp=modecycle[i];
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,modetemp);
          digitalWrite(latchPin,HIGH);
          delay(500);
        }
    }

    while(mode == 2 ){//input the first cons by changeable resistor
      calcucons1 = analogRead(6)/115;//get the first number we need to calculate
      temp = cons[calcucons1];
      digitalWrite(latchPin,LOW);
      shiftOut(dataPin,clockPin,MSBFIRST,temp);
      digitalWrite(latchPin,HIGH);
      delay(500);
    }
    while(mode == 3){//tip for second step by shiny between the dot and 2
        for(int i = 2;i < 4;i++){
          modetemp=modecycle[i];
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,modetemp);
          digitalWrite(latchPin,HIGH);
          delay(500);
        }
    }
    while(mode == 4){//choose the way to calculation , 1 = "+", 2 = "-" , 3 = "*" , 4 = "/"
      wayforcalcu = analogRead(6)/300;//get the way we need to calculate
      temp = cons[wayforcalcu];
      digitalWrite(latchPin,LOW);
      shiftOut(dataPin,clockPin,MSBFIRST,temp);
      digitalWrite(latchPin,HIGH);
      delay(500);
    }
    while(mode == 5){//tip for third step two by shiny between the dot and 3
        for(int i = 4;i < 6;i++){
          modetemp=modecycle[i];
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,modetemp);
          digitalWrite(latchPin,HIGH);
          delay(500);
        }
    }
    while(mode == 6){//input the first cons by changeable resistor
      calcucons2 = analogRead(6)/115;//get the second number we need to calculate
      temp = cons[calcucons2];
      digitalWrite(latchPin,LOW);
      shiftOut(dataPin,clockPin,MSBFIRST,temp);
      digitalWrite(latchPin,HIGH);
      delay(500);
    }
    while(mode == 7){//tip for forth step two by shiny between the dot and 4
        for(int i = 6;i < 8;i++){
          modetemp=modecycle[i];
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,modetemp);
          digitalWrite(latchPin,HIGH);
          delay(500);
        }
    }
    result = calculate();
    while(mode == 8){//show the result of calculation
        if(result < 0){
          int result1 = result * (-1);//change the number to positive
          int result1a = resultar[result1];
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,127);//show the sign of negative
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,result1a); //show the negative number
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,255);
          digitalWrite(latchPin,HIGH);
          delay(1000);
        }
        else if(result > 9 ){
          int result1 = result / 10;//change the result into the type that 7-segment can show normal
          int result2 = result - (result1 * 10);
          int result1a = resultar[result1];
          int result2a = resultar[result2];
          while(mode == 8){
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,result1a);
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,result2a);
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,255);
          digitalWrite(latchPin,HIGH);
          delay(1000);
          }
        }
        else if(result - floor(result) != 0){
int result1 = floor(result); //change the result into the type that 7-segment can show normal
        int result2 = floor((result - float(result1)) * 10);
        int result3 = floor((((result - float(result1)) * 10) - float(result2)) * 10);
        int result1a = resultar[result1];
        int result2a = resultar[result2];
        int result3a = resultar[result3];
          while(mode == 8){
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,result1a);
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,254);
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,result2a);
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,result3a);
          digitalWrite(latchPin,HIGH);
          delay(500);
          digitalWrite(latchPin,LOW);
          shiftOut(dataPin,clockPin,MSBFIRST,255);
          digitalWrite(latchPin,HIGH);
          delay(1000);
          }
        }
        else{
          while(mode == 8){
            int result1 = floor(result);
            int result1a = resultar[result1];
            digitalWrite(latchPin,LOW);
            shiftOut(dataPin,clockPin,MSBFIRST,result1a);
            digitalWrite(latchPin,HIGH);
            delay(500);
            digitalWrite(latchPin,LOW);
            shiftOut(dataPin,clockPin,MSBFIRST,255);
            digitalWrite(latchPin,HIGH);
            delay(1000);
          }
        }
    }
  }

  float calculate(){
      switch(wayforcalcu){
        case 0:
          return (calcucons1+1 + calcucons2+1);

        case 1:
          return((calcucons1+1) - (calcucons2+1));

        case 2:
          return((calcucons1+1) * (calcucons2+1));

        case 3:
          float  float1 = ((float(calcucons1)+1) / (float(calcucons2)+1));
          return float1;

      }
    }
