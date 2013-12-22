// Дверь в общаге v2.0
// Авторы: Рыбин Сергей (http://vk.com/sergey_js) и Рагозин Роман (http://vk.com/romk_js)
// Видео ее работы: http://www.youtube.com/watch?v=YcNlgM4OFmo

// !!! Внимание !!!
// Это наш первый проект на Arduino, поэтому здесь много чего сделано "не так, как надо", в том числе все конструкции и крепления делались из подручных средств, поэтому выглядят "как на соплях".
// Но тем не менее у нас "Дверь" работает :)
// В коде программы и в комментариях могут быть ошибки, причем в коде их может быть много, что-то наверняка сделано не рационально, что-то учитывает не все случаи, что-то у кого-то и вовсе работать не будет.
// Этот код это всего лишь образец, который далеко не идеален.

// Итак, вот важные замечания:

// Перед использованием скетча, необходимо подключить все библиотеки
// Эта версия "Двери" БЕЗ использования резервного питания. При желании, вы можете подлкючить его самостоятельно
// Проверка, закрыта ли дверь, осуществляется путем замыкания двух контактов, расположенных на торце и коробке двери при закрытии
// Когда сервопривод не используется, питание к нему выключается NPN транзистором. Это сделано потому, что сервопривод издает неприятный высокочастотный звук, когда к нему подведено питание. В общем, мешало спать :D

// С RFID сканера в этом коде проверяется просто наличие 3 символов кода, на самом деле код карты гораздо длиннее, но для общаги этого достаточно.
// Это не очень надежно, при желании можно проверять все символы карты. Но для начала их нужно считать, чтобы знать, с чем сверять.
// Причем идет проверка только на 2 различные карты. (Вот, нпример, в строке msg.indexOf('FCE') мы проверяем, есть ли в коде считанной карты эти 3 символа: FCE)
// Вы можете добавить в строку с этим условием через знак '||' любое количество таких проверок, в зависимости от количества используемых различных карт.

// Набросок схемы подключения устройств на Troyka Shield (осторожно, набросок сделан от руки карандашом и может не соответствовать этому коду): http://yadi.sk/d/QKzoA97sEkDMv
// Здесь MOSFET транзистор нужен для управления 12V светодиодной лентой, NPN транзистор нужен для отключения питания от сервопривода, когда он не используется
// Фото фронтальной стороны собранной Troyka Shield (к сожалению из-за большого кол-ва проводов, не все видно): http://yadi.sk/d/7x02yawKEkFCP
// Фото обратной  стороны (на самом деле это все лучше спаять на печатной плате, но мы делали из подручных средств): http://yadi.sk/d/Jwh7kjFEEkFgK

#include <Metro.h> // Библиотека таймера (во всех паузах используется таймер, а не delay, чтобы избежать зависаний процесса во время задержки)
// Ее можно скачать здесь: https://github.com/thomasfredericks/Metro-Arduino-Wiring
// Затем ее необходимо подключить через Скетч->Импортировать библиотеку->Add Library...

// Эти библиотеки стандартные, должны работать без дополнительного подключения
#include <Servo.h> // Библиотека для управления сервоприводом
#include <SoftwareSerial.h> // Библиотека нужна для считывания данных с RFID сканера

#define ledPin1 2 // Pin для светодиода индикации состояния двери (внутри комнаты)
#define ledPin2 3 // Pin для светодиода индикации состояния двери (снуражи комнаты)
#define servoPowerPin 4 // Pin для питания сервопривода
#define insideOpen 6 // Pin для кнопки открытия двери внутри комнаты 
#define doorPin 7 // Pin для контактов, которые замыкаются при закрытии двери (работает аналогично кнопке)
#define reserveOpen 5 // Pin для контактов резервного открытия двери, в случае, если забыл RFID карту или в случае отказа RFID сканера (да, да, такое тоже случается :D)
#define pirPin 8 // Pin для инфракрасного датчика движения
#define rfPin 9 // Pin для RFID сканера (получает данные приложенной карты)
#define servoPin 10 // Pin для усправления сервоприводом щеколды замка
#define fadePin 11 // Pin для управления светодиодной лентой
#define angle 35 // Здесь задается угол поворота сервопривода, в зависимости от того, насколько длинный ход щеколды у замка
#define calibrationTime 60 // Это время калибровки инфракрасного датчика движения (чем выше, тем более точно будет реагировать на движение, 60 с. в самый раз)
// В течение этого времени после запуска Arduino не должно быть никого в поле его видимости. На время калибровки Arduino не будет ни на что реагировать.

Metro servoMetro = Metro(3000); // Задаем время, в течение которого после открытия замка должна быть открыта непосредственно сама дверь. Иначе через это время замок закроется обратно
int pos; // Переменная для считывания текущего положения сервопривода
boolean lockLow = true; // Переменная для проверки, было ли обнаружено движение, если true, то еще нет.
// Она нужна для корректной работы задержки перед выключением света, а также корректной работы включения света, в период, когда свет уже начал гаснуть, но движение появилось вновь, чтобы не дожидался, пока он полностью погаснет, а сразу начал его снова включать.
boolean takeLowTime; // Тоже для инфракрасного датчика, но нужна для того, чтобы после того, как узнали время окончания движения, больше его не считывать
boolean motionDetLed = false; // Показывает, должна ли светодиодная лента быть включенной
long unsigned int lowIn; // Получает время окончания движения
long unsigned int pause = 8000; // Время, в течении которого мы не проверяем, было ли новое движение. Т. е. по сути это время, в течении которого должна гореть светодиодная лента после обнаружения движения.
String msg; // Переменная, в которую считываем данные RFID карты
char c; // Переменная для посимвольного считывания
int ledState = LOW; // В этой переменной устанавливаем состояние светодиодов (оба светодиода работают синхронно и имеют одинаковую индикацию)
long previousMillis = 0; // Храним время последнего переключения светодиода. Это нужно для реализации быстрого мигания светодиода, когда дверь открыта
long interval = 400; // Интервал между включение/выключением светодиода

int ledI = 0; // Аналоговое значение яркости светодиодной ленты (для плавного включения и выключения света)
boolean ledBon = false; // Если true, то это значит, что свет в процессе включения (т. е. яркость поднимается, но еще не достигла конечной точки)
boolean ledBoff = false; // Если true, то это значит, что свет в процессе выключения (т. е. яркость опускается, но еще не достигла конечной точки)
Servo myservo; // Определяем переменную для работы с сервоприводом
SoftwareSerial rfid = SoftwareSerial(rfPin,12); // Определяем переменную для работы с RFID сканером

void setup(){
  // Задаем типы (ввод или вывод) для соответствующих Pin
  pinMode(fadePin, OUTPUT); 
  pinMode(servoPin, OUTPUT);
  pinMode(servoPowerPin,OUTPUT);  
  pinMode(fadePin,INPUT);
  
  myservo.attach(servoPin); // Связываем Pin сервопривода с соответствующим классом
  servoOpen(); // Функция открытия двери. Запускаем ее при запуске Ардуино для того, чтобы дверь открылась, если до этого она была закрыта
  rfid.begin(9600); // Подлкючаем RFID
  calibrationSensors(); // Запускаем калибровку инфракрасного датчика движения
}

void loop(){
  pos = myservo.read(); // Считываем положение сервопривода

  // В цикле loop выполняем следующие, отдельно написанные, функции
  diodBlink(); // Функция индикации светодиодов
  rfidRead(); // Функция чтения данных с RFID
  buttons(); // Функция обработки кнопок
  moveSensor(); // Функция обнаружения движения
  
  // Слудующий кусок кода плавно включает и выключает светодиодную ленту. Также идет обработка того случая, если светодиодная лента уже начала выключаться, но датчик движения снова обнаружил движение.
  // В этом случае нужно не дожидаться, пока она полностью погаснет, а сразу с той же точки якрости начать увеличивать ее до максимума
  if (ledBon && motionDetLed) {
     if (ledI>=255) {
       ledBon = false; 
     } else {       
       ledI=ledI+1; 
       analogWrite(fadePin,ledI);
       delay(15);
     }
  }
  else {
    motionDetLed = false;
    ledBon = false; 
  }
  
  if ((ledBoff) && (motionDetLed == false)) {
     if (ledI<=0) {
       ledBoff = false; 
     } else {
       ledI=ledI-1; 
       analogWrite(fadePin,ledI);
       delay(15);
     }
  }
  else {
    ledBoff = false; 
  }
 
}

// Функция обработки кнопок
void buttons() { 
 
  // Здесь идет проверка, на закрытие непсоредственно самой двери (т. е. замыкания контактов на ее торце).
  // Для этого были использованы обычные канцелярские кнопки: http://yadi.sk/d/BY2PPszsEkQ5M
  // Также, здесь проверяется, если замок был открыт, но в течение 3 сек. дверь не была открыта, то замок автоматически закрывается
  if ((digitalRead(doorPin) == HIGH)&&(servoMetro.check()==1))
  {
     servoClose(); // Функция закрытия сервоприводом замка
  }  
  
  // Здесь идет проверка как на нажатие кнопки открытия внутри комнаты, так и на замыкание резервной кнопки
  if ((digitalRead(insideOpen)==HIGH) || (digitalRead(reserveOpen)==HIGH)) {
      servoOpen(); // Функция открытия сервоприводом замка
  } 
  
}


// Функция индикации светодиодов
void diodBlink() {
  
  unsigned long currentMillis = millis();
 
  // Если замок открыт, т. е. угол поворота сервопривода равен нашему значению его октрытия, то светодиод должен быстро мигать
  if (pos==angle) {
  // Проверяем, не прошел ли нужный интервал, если прошел, то
  if(currentMillis - previousMillis > interval) {
    // Сохраняем время последнего переключения
    previousMillis = currentMillis;  

    // Если светодиод не горит, то зажигаем, иначе выключаем
    if (ledState == LOW)
      ledState = HIGH;
    else
      ledState = LOW;

    // Устанавливаем состояния выходов, чтобы включить или выключить светодиод для обоих светодиодов
    digitalWrite(ledPin1, ledState);
    digitalWrite(ledPin2, ledState);
  }
  } else {
    digitalWrite(ledPin1, HIGH);
    digitalWrite(ledPin2, HIGH);
  }
  
}


// Функция чтения данных с RFID
void rfidRead() {
  
 if(rfid.available()>0) {
   while(rfid.available()>0){ // считываем данные посимвольно
    c=rfid.read(); 
    msg += c;
  }
  delay(20);
 }
 
  msg=msg.substring(1,13); //вырезаем код, т. е. только те символы, которые нам нужны для идентификации карты
  
  // Если эта карта разрешенная, то открываем дверь
  // Здесь через знак || можно добавлять дополнительные карты для проверки
  // Также, можно сравнивать по большему количеству символов для большей защищенности
  if ((msg.indexOf('FCE')>=0)||(msg.indexOf('28C')>=0)) { 
      servoOpen(); // Открываем замок    
  } 
   msg = ""; // Очищаем переменную для возможности считывания новой карты
}

// Функция обнаружения движения
void moveSensor() {
  
  // Если обнаружено движение, то
  if (digitalRead(pirPin) == HIGH) {
     //Если еще не вывели информацию об обнаружении
     if(lockLow) {
       lockLow = false;     
       ledBon = true;
       motionDetLed = true;
       delay(50);
     }        
     takeLowTime = true;
   }
  //Ели движения нет, то
   if (digitalRead(pirPin) == LOW)
   {      
     // Если время окончания движения еще не записано
     if(takeLowTime)
     {
       lowIn = millis();          // Сохраним время окончания последнего движения
       takeLowTime = false;       // Изменим значения флага, чтобы больше не брать время, пока не будет нового движения
     }
     
     //Если время без движение превышает паузу => движение окончено
     if(!lockLow && millis() - lowIn > pause)
     { 
       //Изменяем значение флага, чтобы эта часть кода исполнилась лишь раз, до нового движения
       lockLow = true;               
       ledBoff = true;
       motionDetLed = false;
       delay(50);
     }
   } 
}

// Калибровка сенсора
void calibrationSensors() {
   for(int i = 0; i < calibrationTime; i++)
   {
     delay(1000);
   }
}


// Открытие замка
void servoOpen() {
    digitalWrite(servoPowerPin,HIGH); // Включаем питание сервопривода подачей напряжения на запирающий транзистор
    delay(100); // Задержка, чтобы сервопривод успел начать принимать данные после подключения к нему питания
    myservo.write(angle); // Поворачиваем сервопривод на угол angle
    delay(500); // Эта задержка нужна, чтобы сервопривод успел передвинуть щеколду до момента отключения от него питания
    digitalWrite(servoPowerPin,LOW); // Отключаем питание сервопривода
    servoMetro.reset(); // Сбрасываем таймер для нвоого отсчета, чтобы если дверь не была открыта в течении 3-х секунд, закрыть замок обратно
}


// Закрытие замка
void servoClose() {
    digitalWrite(servoPowerPin,HIGH); // Включаем питание сервопривода подачей напряжения на запирающий транзистор
    delay(100);
    myservo.write(0);
    delay(500);  
    digitalWrite(servoPowerPin,LOW); // Отключаем питание сервопривода
}

