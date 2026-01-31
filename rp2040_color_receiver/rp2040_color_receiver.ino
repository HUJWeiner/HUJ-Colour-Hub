/*
 * RP2040-Zero Color Pattern Receiver with EEPROM Storage
 * Receives JSON color patterns via USB Serial and saves to EEPROM
 *
 * NOTE: Inverted PWM - 0 = FULL ON, 255 = FULL OFF
 */

#include <ArduinoJson.h>
#include <EEPROM.h>

#define FIRMWARE_VERSION "v0.9.0"

const int RED_PIN   = 7;
const int GREEN_PIN = 8;
const int BLUE_PIN  = 6;

// EEPROM Configuration
#define EEPROM_SIZE 2048
#define EEPROM_MAGIC 0xCAFE
#define EEPROM_ADDR_MAGIC 0
#define EEPROM_ADDR_DATA 2

// Pattern state variables
StaticJsonDocument<1536> currentPatternDoc;
int currentPatternCount = 0;
int currentColorIndex = 0;
unsigned long lastColorChange = 0;
unsigned long colorDuration = 1000; // 1 second per color by default
String currentTransition = "instant";
bool isRainbowMode = false; // For continuous rainbow cycling
int rainbowHue = 0; // Current hue for rainbow mode
int rainbowSpeed = 50; // Speed percentage (1-100)
int rainbowBrightness = 100; // Brightness percentage (1-100)

void setup() {
  // Initialize USB Serial and wait for connection
  Serial.begin(115200);
  
  // Set up RGB LED pins (INVERTED: 0=ON, 255=OFF)
  analogWriteResolution(8); // 0-255 range
  pinMode(RED_PIN, OUTPUT);
  pinMode(GREEN_PIN, OUTPUT);
  pinMode(BLUE_PIN, OUTPUT);
  
  // Start with LEDs off (255 = OFF in inverted mode)
  setRGBColor(0, 0, 0);
  
  // Wait for USB Serial to be ready (important for RP2040)
  unsigned long startTime = millis();
  while (!Serial && (millis() - startTime < 3000)) {
    delay(10);
  }
  
  // Initialize EEPROM
  EEPROM.begin(EEPROM_SIZE);
  
  Serial.println("RP2040 Ready with EEPROM Storage");
  
  // Load saved pattern from EEPROM
  loadPatternFromEEPROM();
  
  // Apply the loaded pattern if it exists
  if (currentPatternCount > 0) {
    Serial.print("Loaded saved pattern with ");
    Serial.print(currentPatternCount);
    Serial.println(" colors");
    applyCurrentPattern();
  } else {
    Serial.println("No saved pattern found");
  }
}

void loop() {
  // Handle USB Serial input
  if (Serial.available()) {
    String jsonString = Serial.readStringUntil('\n');
    jsonString.trim(); // Remove whitespace

    if (jsonString.length() > 0) {
      // Check for GET_VERSION command
      if (jsonString == "GET_VERSION") {
        Serial.print("{\"version\":\"");
        Serial.print(FIRMWARE_VERSION);
        Serial.println("\"}");
      }
      // Check for GET_PATTERN command
      else if (jsonString == "GET_PATTERN") {
        sendCurrentPattern();
      } else {
        // Try to parse as JSON pattern
        StaticJsonDocument<1536> doc;
        DeserializationError error = deserializeJson(doc, jsonString);

        if (!error) {
          int count = doc["count"];
          const char* transition = doc["transition"] | "instant";
          JsonArray pattern = doc["pattern"];

          // Extract rainbow-specific parameters if present
          if (doc.containsKey("speed")) {
            rainbowSpeed = doc["speed"];
          }
          if (doc.containsKey("brightness")) {
            rainbowBrightness = doc["brightness"];
          }

          // Send acknowledgment
          Serial.println("Pattern received");

          // Save pattern to EEPROM
          savePatternToEEPROM(doc);

          // Store pattern in memory
          currentPatternDoc.clear();
          currentPatternDoc.set(doc);
          currentPatternCount = count;
          currentTransition = String(transition);

          // Apply the pattern
          applyCurrentPattern();
        } else {
          Serial.println("JSON parse error");
        }
      }
    }
  }

  // Handle pattern cycling (for multi-color patterns)
  handlePatternCycling();

  // Handle rainbow cycling (for color_wheel mode)
  handleRainbowCycling();
}

void savePatternToEEPROM(JsonDocument& doc) {
  // Serialize JSON to string
  String jsonString;
  serializeJson(doc, jsonString);
  
  // Check if it fits in EEPROM
  if (jsonString.length() > (EEPROM_SIZE - 4)) {
    Serial.println("Pattern too large for EEPROM!");
    return;
  }
  
  // Write magic number to indicate valid data
  EEPROM.put(EEPROM_ADDR_MAGIC, EEPROM_MAGIC);
  
  // Write JSON string length
  uint16_t len = jsonString.length();
  EEPROM.put(EEPROM_ADDR_DATA, len);
  
  // Write JSON string
  for (uint16_t i = 0; i < len; i++) {
    EEPROM.write(EEPROM_ADDR_DATA + 2 + i, jsonString[i]);
  }
  
  // Commit to flash
  EEPROM.commit();
  
  Serial.println("Pattern saved to EEPROM");
}

void loadPatternFromEEPROM() {
  // Check magic number
  uint16_t magic;
  EEPROM.get(EEPROM_ADDR_MAGIC, magic);
  
  if (magic != EEPROM_MAGIC) {
    Serial.println("No valid pattern in EEPROM");
    currentPatternCount = 0;
    return;
  }
  
  // Read JSON string length
  uint16_t len;
  EEPROM.get(EEPROM_ADDR_DATA, len);
  
  if (len == 0 || len > (EEPROM_SIZE - 4)) {
    Serial.println("Invalid pattern length in EEPROM");
    currentPatternCount = 0;
    return;
  }
  
  // Read JSON string
  String jsonString = "";
  jsonString.reserve(len);
  for (uint16_t i = 0; i < len; i++) {
    jsonString += (char)EEPROM.read(EEPROM_ADDR_DATA + 2 + i);
  }
  
  // Parse JSON
  DeserializationError error = deserializeJson(currentPatternDoc, jsonString);
  
  if (error) {
    Serial.print("Failed to parse EEPROM pattern: ");
    Serial.println(error.c_str());
    currentPatternCount = 0;
    return;
  }
  
  // Extract pattern info
  currentPatternCount = currentPatternDoc["count"] | 0;
  currentTransition = currentPatternDoc["transition"] | "instant";
  currentColorIndex = 0;
  lastColorChange = millis();
  
  Serial.println("Pattern loaded from EEPROM successfully");
}

void sendCurrentPattern() {
  if (currentPatternCount == 0) {
    Serial.println("No pattern loaded");
    return;
  }

  // Send the current pattern as JSON
  String jsonString;
  serializeJson(currentPatternDoc, jsonString);
  Serial.println(jsonString);

  Serial.print("Sent pattern with ");
  Serial.print(currentPatternCount);
  Serial.println(" colors");
}

void applyCurrentPattern() {
  if (currentPatternCount == 0) {
    // No colors - turn off LED (255 = OFF in inverted mode)
    setRGBColor(0, 0, 0);
    isRainbowMode = false;
    return;
  }

  currentColorIndex = 0;
  lastColorChange = millis();
  rainbowHue = 0;

  // Check if this is rainbow mode (color_wheel transition)
  isRainbowMode = (currentTransition == "color_wheel");

  if (isRainbowMode) {
    Serial.println("Entering Rainbow Mode - continuous cycling");
    // Start the rainbow animation
    colorWheelToColor(255, 255, 255); // Initial rainbow cycle
    return;
  }

  JsonArray pattern = currentPatternDoc["pattern"];

  if (currentPatternCount == 1) {
    // Single color - apply directly
    int r = pattern[0]["r"];
    int g = pattern[0]["g"];
    int b = pattern[0]["b"];

    applyColorWithTransition(r, g, b, currentTransition.c_str());
  } else {
    // Multiple colors - start with first color
    int r = pattern[0]["r"];
    int g = pattern[0]["g"];
    int b = pattern[0]["b"];

    if (currentTransition == "instant") {
      setRGBColor(r, g, b);
    } else {
      applyColorWithTransition(r, g, b, currentTransition.c_str());
    }
  }

  // Debug output
  Serial.print("Applied pattern with ");
  Serial.print(currentPatternCount);
  Serial.print(" colors, transition: ");
  Serial.println(currentTransition);
}

void handlePatternCycling() {
  unsigned long currentTime = millis();

  // Check if we need to loop single-color animations
  if (currentPatternCount == 1) {
    // Check if this transition should loop
    bool shouldLoop = (currentTransition == "fade" ||
                      currentTransition == "pulse" ||
                      currentTransition == "strobe" ||
                      currentTransition == "breathe" ||
                      currentTransition == "bounce" ||
                      currentTransition == "blink" ||
                      currentTransition == "heartbeat" ||
                      currentTransition == "smooth" ||
                      currentTransition == "sparkle");

    if (shouldLoop && currentTime - lastColorChange >= colorDuration) {
      lastColorChange = currentTime;
      JsonArray pattern = currentPatternDoc["pattern"];
      int r = pattern[0]["r"];
      int g = pattern[0]["g"];
      int b = pattern[0]["b"];
      applyColorWithTransition(r, g, b, currentTransition.c_str());
    }
    return;
  }

  // Cycle through multiple colors
  if (currentPatternCount > 1 && currentTime - lastColorChange >= colorDuration) {
    currentColorIndex = (currentColorIndex + 1) % currentPatternCount;
    lastColorChange = currentTime;

    JsonArray pattern = currentPatternDoc["pattern"];
    int r = pattern[currentColorIndex]["r"];
    int g = pattern[currentColorIndex]["g"];
    int b = pattern[currentColorIndex]["b"];

    Serial.print("Cycling to color ");
    Serial.print(currentColorIndex + 1);
    Serial.print("/");
    Serial.print(currentPatternCount);
    Serial.print(" - RGB(");
    Serial.print(r);
    Serial.print(",");
    Serial.print(g);
    Serial.print(",");
    Serial.print(b);
    Serial.println(")");

    applyColorWithTransition(r, g, b, currentTransition.c_str());
  }
}

void handleRainbowCycling() {
  // Only cycle if we're in rainbow mode
  if (!isRainbowMode) return;

  unsigned long currentTime = millis();

  // Calculate delay based on speed (1-100%) - slower speed = longer delay
  // Speed 100% = 10ms, Speed 50% = 20ms, Speed 1% = 200ms
  int delayMs = map(rainbowSpeed, 1, 100, 200, 10);

  // Update rainbow based on speed
  if (currentTime - lastColorChange >= delayMs) {
    lastColorChange = currentTime;

    // Increment hue (0-255) - speed affects how fast we cycle
    int increment = map(rainbowSpeed, 1, 100, 1, 3); // Faster speed = bigger jumps
    rainbowHue = (rainbowHue + increment) % 256;

    // Convert HSV to RGB with brightness control
    int r, g, b;
    int brightness = map(rainbowBrightness, 0, 100, 0, 255);
    hsvToRgb(rainbowHue, 255, brightness, r, g, b);

    setRGBColor(r, g, b);
  }
}

void setRGBColor(int r, int g, int b) {
  // INVERTED: 0 = FULL ON, 255 = FULL OFF
  analogWrite(RED_PIN, 255 - r);
  analogWrite(GREEN_PIN, 255 - g);
  analogWrite(BLUE_PIN, 255 - b);
}

void fadeToColor(int targetR, int targetG, int targetB, int fadeSpeed = 50) {
  // Get current color values (approximate - we don't track exact current state)
  // For simplicity, we'll fade from black. You could track current RGB if needed.

  int steps = fadeSpeed;

  for (int step = 0; step <= steps; step++) {
    int r = (targetR * step) / steps;
    int g = (targetG * step) / steps;
    int b = (targetB * step) / steps;

    setRGBColor(r, g, b);
    delay(10);
  }
}

void pulseToColor(int targetR, int targetG, int targetB) {
  // Pulse effect: fade in, hold, fade out, then set final color

  // Fade in
  for (int brightness = 0; brightness <= 255; brightness += 5) {
    int r = (targetR * brightness) / 255;
    int g = (targetG * brightness) / 255;
    int b = (targetB * brightness) / 255;
    setRGBColor(r, g, b);
    delay(8);
  }

  // Hold
  delay(200);

  // Fade out
  for (int brightness = 255; brightness >= 0; brightness -= 5) {
    int r = (targetR * brightness) / 255;
    int g = (targetG * brightness) / 255;
    int b = (targetB * brightness) / 255;
    setRGBColor(r, g, b);
    delay(8);
  }

  // Set final color
  setRGBColor(targetR, targetG, targetB);
}

void strobeToColor(int targetR, int targetG, int targetB) {
  // Strobe effect: rapid on/off flashing
  for (int i = 0; i < 5; i++) {
    setRGBColor(targetR, targetG, targetB);
    delay(50);
    setRGBColor(0, 0, 0);
    delay(50);
  }
  setRGBColor(targetR, targetG, targetB);
}

void bounceToColor(int targetR, int targetG, int targetB) {
  // Bounce effect: overshoot then settle (like elastic)
  int steps = 40;

  for (int step = 0; step <= steps; step++) {
    float t = (float)step / steps;
    // Elastic overshoot formula
    float overshoot = 1.0 + sin((t - 1.0) * 3.14159 * 2.5) * exp(-(t * 5));

    int r = constrain((int)(targetR * overshoot), 0, 255);
    int g = constrain((int)(targetG * overshoot), 0, 255);
    int b = constrain((int)(targetB * overshoot), 0, 255);

    setRGBColor(r, g, b);
    delay(15);
  }

  setRGBColor(targetR, targetG, targetB);
}

void breatheToColor(int targetR, int targetG, int targetB) {
  // Breathe effect: smooth sine wave fade in and out
  int steps = 60;

  // Fade in (sine wave)
  for (int step = 0; step <= steps; step++) {
    float t = (float)step / steps;
    float sine = sin(t * 3.14159 / 2.0); // 0 to PI/2

    int r = (int)(targetR * sine);
    int g = (int)(targetG * sine);
    int b = (int)(targetB * sine);

    setRGBColor(r, g, b);
    delay(12);
  }

  delay(300);

  // Fade out
  for (int step = steps; step >= 0; step--) {
    float t = (float)step / steps;
    float sine = sin(t * 3.14159 / 2.0);

    int r = (int)(targetR * sine);
    int g = (int)(targetG * sine);
    int b = (int)(targetB * sine);

    setRGBColor(r, g, b);
    delay(12);
  }

  delay(200);
  setRGBColor(targetR, targetG, targetB);
}

void blinkToColor(int targetR, int targetG, int targetB) {
  // Blink effect: off briefly, then show color
  setRGBColor(0, 0, 0);
  delay(200);
  setRGBColor(targetR, targetG, targetB);
  delay(100);
  setRGBColor(0, 0, 0);
  delay(100);
  setRGBColor(targetR, targetG, targetB);
}

void colorWheelToColor(int targetR, int targetG, int targetB) {
  // Color wheel effect: cycle through spectrum to reach target
  // This is actually a rainbow cycle mode - shows full spectrum
  int steps = 100;

  for (int step = 0; step < steps; step++) {
    int hue = (step * 255) / steps;

    // Convert HSV to RGB (V = 255, S = 255)
    int r, g, b;
    hsvToRgb(hue, 255, 255, r, g, b);

    setRGBColor(r, g, b);
    delay(20);
  }

  setRGBColor(targetR, targetG, targetB);
}

void heartbeatToColor(int targetR, int targetG, int targetB) {
  // Heartbeat effect: double pulse pattern

  // First pulse
  for (int brightness = 0; brightness <= 255; brightness += 15) {
    int r = (targetR * brightness) / 255;
    int g = (targetG * brightness) / 255;
    int b = (targetB * brightness) / 255;
    setRGBColor(r, g, b);
    delay(5);
  }

  for (int brightness = 255; brightness >= 100; brightness -= 15) {
    int r = (targetR * brightness) / 255;
    int g = (targetG * brightness) / 255;
    int b = (targetB * brightness) / 255;
    setRGBColor(r, g, b);
    delay(5);
  }

  delay(50);

  // Second pulse
  for (int brightness = 100; brightness <= 255; brightness += 15) {
    int r = (targetR * brightness) / 255;
    int g = (targetG * brightness) / 255;
    int b = (targetB * brightness) / 255;
    setRGBColor(r, g, b);
    delay(5);
  }

  for (int brightness = 255; brightness >= 0; brightness -= 15) {
    int r = (targetR * brightness) / 255;
    int g = (targetG * brightness) / 255;
    int b = (targetB * brightness) / 255;
    setRGBColor(r, g, b);
    delay(5);
  }

  delay(300);
  setRGBColor(targetR, targetG, targetB);
}

void smoothToColor(int targetR, int targetG, int targetB) {
  // Smooth effect: ease-in-out curve for more natural motion
  int steps = 50;

  for (int step = 0; step <= steps; step++) {
    float t = (float)step / steps;

    // Ease-in-out formula: smooth acceleration and deceleration
    float ease;
    if (t < 0.5) {
      ease = 2 * t * t;
    } else {
      ease = 1.0 - pow(-2 * t + 2, 2) / 2;
    }

    int r = (int)(targetR * ease);
    int g = (int)(targetG * ease);
    int b = (int)(targetB * ease);

    setRGBColor(r, g, b);
    delay(10);
  }

  setRGBColor(targetR, targetG, targetB);
}

void sparkleToColor(int targetR, int targetG, int targetB) {
  // Sparkle effect: random brightness flickers before settling

  for (int i = 0; i < 15; i++) {
    int randomBrightness = random(50, 255);
    int r = (targetR * randomBrightness) / 255;
    int g = (targetG * randomBrightness) / 255;
    int b = (targetB * randomBrightness) / 255;

    setRGBColor(r, g, b);
    delay(random(30, 80));
  }

  setRGBColor(targetR, targetG, targetB);
}

// Helper function to convert HSV to RGB
void hsvToRgb(int h, int s, int v, int &r, int &g, int &b) {
  if (s == 0) {
    r = g = b = v;
    return;
  }

  int region = h / 43;
  int remainder = (h - (region * 43)) * 6;

  int p = (v * (255 - s)) >> 8;
  int q = (v * (255 - ((s * remainder) >> 8))) >> 8;
  int t = (v * (255 - ((s * (255 - remainder)) >> 8))) >> 8;

  switch (region) {
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    default: r = v; g = p; b = q; break;
  }
}

void applyColorWithTransition(int targetR, int targetG, int targetB, const char* transition) {
  if (strcmp(transition, "instant") == 0) {
    setRGBColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "fade") == 0) {
    fadeToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "pulse") == 0) {
    pulseToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "strobe") == 0) {
    strobeToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "bounce") == 0) {
    bounceToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "breathe") == 0) {
    breatheToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "blink") == 0) {
    blinkToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "color_wheel") == 0) {
    colorWheelToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "heartbeat") == 0) {
    heartbeatToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "smooth") == 0) {
    smoothToColor(targetR, targetG, targetB);

  } else if (strcmp(transition, "sparkle") == 0) {
    sparkleToColor(targetR, targetG, targetB);

  } else {
    // Default to instant
    setRGBColor(targetR, targetG, targetB);
  }
}
