li#include <ESP8266WiFi.h>

const char* ssid       = "guardian";
const char* password   = "123456789";
const char* serverHost = "10.42.0.1";
const uint16_t serverPort = 8765;

WiFiClient client;

// Button pins
#define BTN1 D1
#define BTN2 D2
#define BTN3 D3
#define BTN4 D4

bool last1 = HIGH, last2 = HIGH, last3 = HIGH, last4 = HIGH;

unsigned long lastWiFiCheck = 0;
unsigned long lastTCPCheck  = 0;

void setup() {
  Serial.begin(115200);
  pinMode(BTN1, INPUT_PULLUP);
  pinMode(BTN2, INPUT_PULLUP);
  pinMode(BTN3, INPUT_PULLUP);
  pinMode(BTN4, INPUT_PULLUP);

  connectWiFi();
  connectTCP();
}

void loop() {
  // Button handling only when connected
  if (client.connected()) {
    checkButton(BTN1, last1, "Fire:Location1");
    checkButton(BTN2, last2, "Fire:Location2");
    checkButton(BTN3, last3, "Fire:Location3");
    checkButton(BTN4, last4, "Fire:Location4");
  }

  // Periodic WiFi check
  if (millis() - lastWiFiCheck > 2000) {
    lastWiFiCheck = millis();
    if (WiFi.status() != WL_CONNECTED) {
      connectWiFi();
    }
  }

  // Periodic TCP reconnect
  if (millis() - lastTCPCheck > 3000) {
    lastTCPCheck = millis();
    if (!client.connected() && WiFi.status() == WL_CONNECTED) {
      connectTCP();
    }
  }
}

// ---------------- WiFi ----------------
void connectWiFi() {
  Serial.printf("Connecting WiFi: %s\n", ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) { delay(400); Serial.print("."); }
  Serial.printf("\nWiFi OK, IP: %s\n", WiFi.localIP().toString().c_str());
}

// ---------------- TCP ----------------
void connectTCP() {
  Serial.printf("Connecting TCP %s:%d\n", serverHost, serverPort);
  if (client.connect(serverHost, serverPort)) {
    Serial.println("TCP connected");
    sendIdentify();
  } else {
    Serial.println("TCP connect failed");
  }
}

void sendIdentify() {
  // newline-terminated JSON
  String msg = "{\"command\":\"identify\",\"client_type\":\"external_client\"}\n";
  client.print(msg);
  client.flush();
  Serial.println("Sent identify");
}

void sendFire(const char* token) {
  String msg = String(token) + "\n"; // plain text token with newline
  client.print(msg);
  client.flush();
  Serial.printf("Sent fire token: %s\n", token);
}

// -------------- Buttons --------------
void checkButton(int pin, bool &lastState, const char* token) {
  bool current = digitalRead(pin);
  if (current == LOW && lastState == HIGH) {
    if (client.connected()) sendFire(token);
    else Serial.println("TCP not connected; skipped");
    delay(200); // debounce
  }
  lastState = current;
}
