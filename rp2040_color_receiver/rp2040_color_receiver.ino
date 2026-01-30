/*
 * RP2040-Zero Color Pattern Receiver with EEPROM Storage
 * Receives JSON color patterns via USB Serial and saves to EEPROM
 * 
 * NOTE: Inverted PWM - 0 = FULL ON, 255 = FULL OFF
 */

#include <ArduinoJson.h>
#include <EEPROM.h>

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
      // Check for GET_PATTERN command
      if (jsonString == "GET_PATTERN") {
        sendCurrentPattern();
      } else {
        // Try to parse as JSON pattern
        StaticJsonDocument<1536> doc;
        DeserializationError error = deserializeJson(doc, jsonString);

        if (!error) {
          int count = doc["count"];
          const char* transition = doc["transition"] | "instant";
          JsonArray pattern = doc["pattern"];

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
    return;
  }
  
  currentColorIndex = 0;
  lastColorChange = millis();
  
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
  // Only cycle if we have multiple colors
  if (currentPatternCount <= 1) return;
  
  unsigned long currentTime = millis();
  
  // Check if it's time to change to next color
  if (currentTime - lastColorChange >= colorDuration) {
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

void applyColorWithTransition(int targetR, int targetG, int targetB, const char* transition) {
  if (strcmp(transition, "instant") == 0) {
    setRGBColor(targetR, targetG, targetB);
    
  } else if (strcmp(transition, "fade") == 0) {
    fadeToColor(targetR, targetG, targetB);
    
  } else if (strcmp(transition, "pulse") == 0) {
    pulseToColor(targetR, targetG, targetB);
    
  } else if (strcmp(transition, "wipe") == 0) {
    // For single RGB LED, wipe is same as fade but faster
    fadeToColor(targetR, targetG, targetB, 20); // Faster fade
    
  } else {
    // Default to instant
    setRGBColor(targetR, targetG, targetB);
  }
}
