/*
 * RP2040-Zero Color Pattern Receiver
 * Receives JSON color patterns via USB Serial
 */

#include <ArduinoJson.h>

// Configure your LED setup here
// #include <Adafruit_NeoPixel.h>
// #define LED_PIN 16
// #define NUM_LEDS 10
// Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

void setup() {
  Serial.begin(115200);
  delay(500);
  
  // Initialize your LEDs here
  // strip.begin();
  // strip.show();
}

void loop() {
  if (Serial.available()) {
    String jsonString = Serial.readStringUntil('\n');
    
    StaticJsonDocument<2048> doc;
    DeserializationError error = deserializeJson(doc, jsonString);
    
    if (!error) {
      int count = doc["count"];
      const char* transition = doc["transition"] | "instant";
      JsonArray pattern = doc["pattern"];
      
      // Apply the pattern based on transition type
      applyPattern(pattern, count, transition);
    }
  }
}

void applyPattern(JsonArray pattern, int count, const char* transition) {
  // Implement your LED control logic here
  
  if (strcmp(transition, "instant") == 0) {
    // Instant change
    // for (int i = 0; i < count && i < NUM_LEDS; i++) {
    //   int r = pattern[i]["r"];
    //   int g = pattern[i]["g"];
    //   int b = pattern[i]["b"];
    //   strip.setPixelColor(i, strip.Color(r, g, b));
    // }
    // strip.show();
    
  } else if (strcmp(transition, "fade") == 0) {
    // Fade transition
    // int steps = 50;
    // for (int step = 0; step <= steps; step++) {
    //   for (int i = 0; i < count && i < NUM_LEDS; i++) {
    //     int r = pattern[i]["r"] * step / steps;
    //     int g = pattern[i]["g"] * step / steps;
    //     int b = pattern[i]["b"] * step / steps;
    //     strip.setPixelColor(i, strip.Color(r, g, b));
    //   }
    //   strip.show();
    //   delay(20);
    // }
    
  } else if (strcmp(transition, "wipe") == 0) {
    // Wipe transition
    // for (int i = 0; i < count && i < NUM_LEDS; i++) {
    //   int r = pattern[i]["r"];
    //   int g = pattern[i]["g"];
    //   int b = pattern[i]["b"];
    //   strip.setPixelColor(i, strip.Color(r, g, b));
    //   strip.show();
    //   delay(100);
    // }
    
  } else if (strcmp(transition, "pulse") == 0) {
    // Pulse transition
    // for (int pulse = 0; pulse < 3; pulse++) {
    //   for (int brightness = 0; brightness <= 255; brightness += 5) {
    //     strip.setBrightness(brightness);
    //     for (int i = 0; i < count && i < NUM_LEDS; i++) {
    //       int r = pattern[i]["r"];
    //       int g = pattern[i]["g"];
    //       int b = pattern[i]["b"];
    //       strip.setPixelColor(i, strip.Color(r, g, b));
    //     }
    //     strip.show();
    //     delay(10);
    //   }
    //   for (int brightness = 255; brightness >= 0; brightness -= 5) {
    //     strip.setBrightness(brightness);
    //     strip.show();
    //     delay(10);
    //   }
    // }
    // strip.setBrightness(255);
  }
}
