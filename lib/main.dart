import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_cube/flutter_cube.dart';

// 3D LED Ring Viewer Widget using flutter_cube
class LEDRing3DViewer extends StatefulWidget {
  final List<Color> colors;
  final Color glowColor;

  const LEDRing3DViewer({
    super.key,
    required this.colors,
    required this.glowColor,
  });

  @override
  State<LEDRing3DViewer> createState() => _LEDRing3DViewerState();
}

class _LEDRing3DViewerState extends State<LEDRing3DViewer> with SingleTickerProviderStateMixin {
  Object? _ledRingObject;
  Object? _ledsObject;
  Scene? _scene;
  
  // Rotation state
  double _rotationX = -20;
  double _rotationY = 0;
  
  // Momentum animation
  late AnimationController _momentumController;
  double _velocityX = 0;
  double _velocityY = 0;
  Offset? _lastPanPosition;
  DateTime? _lastPanTime;
  
  // Zoom state
  double _zoom = 1.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _momentumController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..addListener(_applyMomentum);
  }

  @override
  void dispose() {
    _momentumController.dispose();
    super.dispose();
  }

  void _applyMomentum() {
    if (_momentumController.isAnimating) {
      // Apply decaying velocity with easeOut curve for natural feel
      final t = _momentumController.value;
      final decay = 1.0 - (t * t); // Quadratic easeOut decay
      final currentVelocityX = _velocityX * decay;
      final currentVelocityY = _velocityY * decay;
      
      setState(() {
        _rotationY += currentVelocityY * 0.001; // Slower momentum
        _rotationX += currentVelocityX * 0.001;
        _updateObjectRotations();
      });
    }
  }

  void _updateObjectRotations() {
    print('🔧 UPDATE ROTATIONS: ledRing=${_ledRingObject != null}, leds=${_ledsObject != null}, scene=${_scene != null}');
    if (_ledRingObject != null) {
      _ledRingObject!.rotation.setValues(_rotationX, _rotationY, 0);
      _ledRingObject!.updateTransform();
      print('🔧 LedRing rotation set to: ${_ledRingObject!.rotation}');
    }
    if (_ledsObject != null) {
      _ledsObject!.rotation.setValues(_rotationX, _rotationY, 0);
      _ledsObject!.updateTransform();
      print('🔧 Leds rotation set to: ${_ledsObject!.rotation}');
    }
    _scene?.update();
  }

  void _onSceneCreated(Scene scene) {
    print('🎬 SCENE CREATED');
    _scene = scene;
    // Set up camera for better viewing angle
    scene.camera.position.z = _zoom;
    scene.camera.position.y = 0.5;
    
    // Load the LED ring model (the base/housing)
    _ledRingObject = Object(fileName: 'assets/ledring.obj', isAsset: true);
    _ledRingObject!.rotation.setValues(_rotationX, _rotationY, 0);
    scene.world.add(_ledRingObject!);
    print('🎬 LedRing object added');
    
    // Load the LEDs model
    _ledsObject = Object(fileName: 'assets/leds.obj', isAsset: true);
    _ledsObject!.rotation.setValues(_rotationX, _rotationY, 0);
    scene.world.add(_ledsObject!);
    print('🎬 Leds object added');
    
    // Apply initial glow color to LEDs
    _updateLEDColor();
  }

  void _updateLEDColor() {
    if (_ledsObject?.mesh != null) {
      final mesh = _ledsObject!.mesh;
      // Convert Flutter Color to Vector3 (RGB normalized to 0-1)
      final r = widget.glowColor.red / 255.0;
      final g = widget.glowColor.green / 255.0;
      final b = widget.glowColor.blue / 255.0;
      // Set the LED material to glow with the selected color
      mesh.material.ambient.setValues(r, g, b);
      mesh.material.diffuse.setValues(r, g, b);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    print('🟢 SCALE START: focalPoint=${details.focalPoint}, pointerCount=${details.pointerCount}');
    _momentumController.stop();
    _lastPanPosition = details.focalPoint;
    _lastPanTime = DateTime.now();
    _velocityX = 0;
    _velocityY = 0;
    _baseZoom = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final now = DateTime.now();
    final delta = details.focalPoint - (_lastPanPosition ?? details.focalPoint);
    final dt = _lastPanTime != null 
        ? now.difference(_lastPanTime!).inMilliseconds / 1000.0 
        : 0.016;
    
    print('🔵 SCALE UPDATE: delta=$delta, pointerCount=${details.pointerCount}, rotX=$_rotationX, rotY=$_rotationY');
    
    // Handle rotation (single finger drag)
    if (details.pointerCount == 1) {
      if (dt > 0 && dt < 0.1) {
        // Calculate velocity with smoothing (exponential moving average)
        // Signs must match the rotation direction below
        final newVelocityY = delta.dx / dt;
        final newVelocityX = delta.dy / dt;
        _velocityY = _velocityY * 0.5 + newVelocityY * 0.5;
        _velocityX = _velocityX * 0.5 + newVelocityX * 0.5;
      }
      
      setState(() {
        _rotationY += delta.dx * 0.15;
        _rotationX += delta.dy * 0.15;
        print('🟡 ROTATION APPLIED: rotX=$_rotationX, rotY=$_rotationY');
        _updateObjectRotations();
      });
    }
    
    // Handle zoom (pinch)
    if (details.pointerCount >= 2) {
      setState(() {
        _zoom = (_baseZoom / details.scale).clamp(0.5, 3.0);
        _scene?.camera.position.z = _zoom;
        _scene?.update();
      });
    }
    
    _lastPanPosition = details.focalPoint;
    _lastPanTime = now;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    print('🔴 SCALE END: velocityX=$_velocityX, velocityY=$_velocityY');
    // Apply momentum if there's any velocity (lowered threshold)
    if (_velocityX.abs() > 50 || _velocityY.abs() > 50) {
      _momentumController.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(LEDRing3DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glowColor != widget.glowColor) {
      _updateLEDColor();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: Container(
        color: const Color(0xFF0A0A0A),
        child: Cube(
          interactive: false, // Disable Cube's internal gesture handling
          onSceneCreated: _onSceneCreated,
        ),
      ),
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LED Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        fontFamily: 'Raleway',
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class SavedPattern {
  final String name;
  final List<Color> colors;
  final String transition;
  final DateTime savedAt;

  SavedPattern({
    required this.name,
    required this.colors,
    required this.transition,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'colors': colors.map((c) => c.value).toList(),
        'transition': transition,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedPattern.fromJson(Map<String, dynamic> json) => SavedPattern(
        name: json['name'],
        colors: (json['colors'] as List).map((c) => Color(c as int)).toList(),
        transition: json['transition'],
        savedAt: DateTime.parse(json['savedAt']),
      );
}

// Global state management for USB connection
class DeviceState extends ChangeNotifier {
  UsbPort? _port;
  UsbDevice? _device;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _showConnecting = false;
  StreamSubscription<UsbEvent>? _usbSubscription;
  StreamSubscription<Uint8List>? _dataSubscription;
  String _incomingData = '';
  List<Color> _currentPatternColours = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.pink,
  ];
  SavedPattern? _currentChipPattern;
  SavedPattern? _patternToCopy;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting && _showConnecting;
  UsbPort? get port => _port;
  List<Color> get currentPatternColours => _currentPatternColours;
  SavedPattern? get currentChipPattern => _currentChipPattern;
  SavedPattern? get patternToCopy => _patternToCopy;

  void updatePatternColours(List<Color> colours) {
    if (colours.isNotEmpty) {
      _currentPatternColours = colours;
      notifyListeners();
    }
  }

  void setPatternToCopy(SavedPattern? pattern) {
    _patternToCopy = pattern;
    notifyListeners();
  }

  Future<void> _saveChipPattern() async {
    if (_currentChipPattern == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_chip_pattern', jsonEncode(_currentChipPattern!.toJson()));
  }

  Future<void> loadChipPattern() async {
    final prefs = await SharedPreferences.getInstance();
    final patternJson = prefs.getString('current_chip_pattern');

    if (patternJson != null) {
      try {
        _currentChipPattern = SavedPattern.fromJson(jsonDecode(patternJson));
        notifyListeners();
      } catch (e) {
        // Invalid pattern data, ignore
      }
    }
  }

  void startUsbMonitoring() {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      _usbSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
        if (event.event == UsbEvent.ACTION_USB_DETACHED) {
          if (_isConnected) {
            disconnect();
          }
        } else if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
          // Auto-connect when device is plugged in
          if (!_isConnected && !_isConnecting) {
            Future.delayed(const Duration(milliseconds: 500), () {
              connect(showConnecting: false);
            });
          }
        }
      });
    } catch (e) {
      // USB monitoring not available
    }
  }

  Future<String> connect({bool showConnecting = true}) async {
    if (kIsWeb || !Platform.isAndroid) {
      return 'USB Serial only works on Android devices';
    }

    _isConnecting = true;
    _showConnecting = showConnecting;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 500));

      List<UsbDevice> devices = await UsbSerial.listDevices();

      if (devices.isEmpty) {
        _isConnecting = false;
        _showConnecting = false;
        notifyListeners();
        return 'No USB device found';
      }

      for (var device in devices) {
        try {
          _device = device;
          _port = await _device!.create();

          if (_port == null) continue;

          bool opened = await _port!.open();

          if (opened) {
            await Future.delayed(const Duration(milliseconds: 300));

            try {
              await _port!.setPortParameters(
                115200,
                UsbPort.DATABITS_8,
                UsbPort.STOPBITS_1,
                UsbPort.PARITY_NONE,
              );
            } catch (e) {
              // Some devices don't support parameter setting
            }

            _isConnected = true;
            _isConnecting = false;
            _showConnecting = false;
            _startDataListener();
            notifyListeners();

            return 'Connected to RP2040';
          }
        } catch (e) {
          continue;
        }
      }

      _isConnecting = false;
      _showConnecting = false;
      notifyListeners();
      return 'Could not connect';
    } catch (e) {
      _isConnecting = false;
      _showConnecting = false;
      notifyListeners();
      return 'Connection error';
    }
  }

  void _startDataListener() {
    if (_port == null) return;

    _dataSubscription = _port!.inputStream?.listen((Uint8List data) {
      String received = utf8.decode(data);
      _incomingData += received;

      if (_incomingData.contains('\n')) {
        List<String> lines = _incomingData.split('\n');
        for (int i = 0; i < lines.length - 1; i++) {
          String line = lines[i].trim();
          if (line.isNotEmpty && line.startsWith('{')) {
            // Try to parse as JSON response
            try {
              final json = jsonDecode(line);

              // Check for pattern response
              if (json['pattern'] != null && json['count'] != null) {
                // This is a pattern response
                List<Color> colors = [];
                for (var colorData in json['pattern']) {
                  colors.add(Color.fromARGB(
                    255,
                    colorData['r'] as int,
                    colorData['g'] as int,
                    colorData['b'] as int,
                  ));
                }
                _currentChipPattern = SavedPattern(
                  name: 'Current Pattern',
                  colors: colors,
                  transition: json['transition'] ?? 'instant',
                  savedAt: DateTime.now(),
                );
                _saveChipPattern();
                notifyListeners();
              }
            } catch (e) {
              // Not a valid JSON, ignore
            }
          }
        }
        _incomingData = lines.last;
      }
    });
  }

  Future<void> disconnect() async {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    await _port?.close();
    _isConnected = false;
    _port = null;
    _device = null;
    _incomingData = '';
    notifyListeners();
  }

  Future<void> sendPattern(Map<String, dynamic> patternData) async {
    if (!_isConnected || _port == null) {
      throw Exception('Not connected to device');
    }

    String jsonString = jsonEncode(patternData);
    await _port!.write(Uint8List.fromList(utf8.encode('$jsonString\n')));
  }

  @override
  void dispose() {
    _usbSubscription?.cancel();
    _dataSubscription?.cancel();
    _port?.close();
    super.dispose();
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final DeviceState _deviceState = DeviceState();
  late PageController _pageController;
  late AnimationController _glowController;
  final GlobalKey<_LibraryScreenState> _libraryKey = GlobalKey<_LibraryScreenState>();
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _deviceState.startUsbMonitoring();
    _deviceState.loadChipPattern(); // Load saved chip pattern

    // Glow animation controller
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Initialize screens once to preserve state
    _screens = [
      PatternCreatorScreen(deviceState: _deviceState),
      LibraryScreen(key: _libraryKey, deviceState: _deviceState),
    ];

    // Auto-connect with retry
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    if (kIsWeb || !Platform.isAndroid) return;

    await Future.delayed(const Duration(milliseconds: 1000));

    // Try up to 3 times (silently, without showing connecting indicator)
    for (int i = 0; i < 3; i++) {
      final result = await _deviceState.connect(showConnecting: false);
      if (result.contains('Connected')) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _glowController.dispose();
    _deviceState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          // Reload patterns when navigating to library tab
          if (index == 1) {
            _libraryKey.currentState?._loadPatterns();
          }
        },
        children: _screens,
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              boxShadow: [
                BoxShadow(
                  color: _getGlowColor().withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.palette_outlined, Icons.palette, 'Create'),
                    _buildNavItem(1, Icons.folder_outlined, Icons.folder, 'Library'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getGlowColor() {
    final glowColours = _deviceState.currentPatternColours;
    if (glowColours.isEmpty) return Colors.grey;

    final t = _glowController.value;
    final index = (t * glowColours.length).floor() % glowColours.length;
    final nextIndex = (index + 1) % glowColours.length;
    final localT = (t * glowColours.length) - index;

    return Color.lerp(glowColours[index], glowColours[nextIndex], localT)!;
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData filledIcon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _currentIndex = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? filledIcon : outlineIcon,
                color: isSelected
                    ? const Color(0xFFFF8C00)
                    : Colors.grey.shade600,
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFF8C00)
                      : Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Pattern Creator Screen
class PatternCreatorScreen extends StatefulWidget {
  final DeviceState deviceState;

  const PatternCreatorScreen({super.key, required this.deviceState});

  @override
  State<PatternCreatorScreen> createState() => _PatternCreatorScreenState();
}

class _PatternCreatorScreenState extends State<PatternCreatorScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<Color> colourPattern = [];
  String _selectedTransition = 'instant';
  late AnimationController _glowController;
  bool _isColourPickerVisible = false;
  Color _pickerColour = Colors.deepPurple;
  int _editingColorIndex = -1; // -1 means adding new, >=0 means editing existing
  int _logoTapCount = 0;
  DateTime? _lastLogoTap;
  double _rotationAngle = 0;

  @override
  bool get wantKeepAlive => true;

  final List<Map<String, String>> _transitions = [
    {'id': 'instant', 'name': 'Instant'},
    {'id': 'fade', 'name': 'Fade'},
    {'id': 'pulse', 'name': 'Pulse'},
    {'id': 'strobe', 'name': 'Strobe'},
    {'id': 'bounce', 'name': 'Bounce'},
    {'id': 'breathe', 'name': 'Breathe'},
    {'id': 'blink', 'name': 'Blink'},
    {'id': 'heartbeat', 'name': 'Heartbeat'},
    {'id': 'sparkle', 'name': 'Sparkle'},
    {'id': 'color_wheel', 'name': 'Rainbow'},
  ];

  double _autoRotateAngle = 0;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Do not pre-populate colours on startup; start with an empty pattern
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                ListenableBuilder(
                  listenable: widget.deviceState,
                  builder: (context, _) {
                    if (widget.deviceState.patternToCopy != null) {
                      return _buildCopyPatternBanner();
                    }
                    return const SizedBox.shrink();
                  },
                ),
                Expanded(
                  child: _selectedTransition == 'color_wheel'
                      ? _buildRainbowWheel()
                      : (colourPattern.isEmpty ? _buildEmptyState() : _build3DVisualization()),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  transform: Matrix4.translationValues(
                    0,
                    _isColourPickerVisible ? -MediaQuery.of(context).size.height * 0.5 : 0,
                    0,
                  ),
                  child: Column(
                    children: [
                      _buildTransitionSelector(),
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ],
            ),
            _buildColourPickerOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: _isColourPickerVisible ? 0 : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isColourPickerVisible ? 0.0 : 1.0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _handleLogoTap,
                  child: Image.asset(
                    'assets/hujlogo.png',
                    height: 80,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              _buildConnectionIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCopyPatternBanner() {
    final pattern = widget.deviceState.patternToCopy!;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF8C00),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.content_copy, color: Color(0xFFFF8C00)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Load "${pattern.name}"?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                colourPattern = List.from(pattern.colors);
                _selectedTransition = pattern.transition;
              });
              widget.deviceState.setPatternToCopy(null);
              _showSnackBar('Pattern loaded!', Icons.check_circle);
            },
            child: const Text('Load', style: TextStyle(color: Color(0xFFFF8C00))),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.deviceState.setPatternToCopy(null);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _handleLogoTap() {
    final now = DateTime.now();
    if (_lastLogoTap != null && now.difference(_lastLogoTap!).inSeconds > 2) {
      _logoTapCount = 0;
    }
    _lastLogoTap = now;
    _logoTapCount++;

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _showSnackBar('Easter egg found! 🎉', Icons.celebration);
    }
  }



  Widget _buildConnectionIndicator() {
    return ListenableBuilder(
      listenable: widget.deviceState,
      builder: (context, _) {
        final isConnected = widget.deviceState.isConnected;
        final isConnecting = widget.deviceState.isConnecting;

        if (isConnecting) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange, width: 2),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Connecting...',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                if (isConnected) {
                  await widget.deviceState.disconnect();
                  _showSnackBar('Disconnected', Icons.power_off);
                } else {
                  final result = await widget.deviceState.connect();
                  _showSnackBar(result, isConnected ? Icons.check_circle : Icons.error);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0xFF00CC00).withOpacity(0.1)
                      : const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isConnected ? const Color(0xFF00CC00) : Colors.red,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isConnected ? Icons.usb : Icons.usb_off,
                      color: isConnected ? const Color(0xFF00CC00) : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: isConnected ? const Color(0xFF00CC00) : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
      },
    );
  }

  Color _getGlowColor() {
    final glowColours = colourPattern.isNotEmpty ? colourPattern : widget.deviceState.currentPatternColours;
    if (glowColours.isEmpty) return Colors.grey;
    if (glowColours.length == 1) return glowColours[0];

    final t = _glowController.value;
    final colors = glowColours;

    switch (_selectedTransition) {
      case 'instant':
        // Instant switch between colors
        final index = (t * colors.length).floor() % colors.length;
        return colors[index];

      case 'fade':
      case 'smooth':
        // Smooth fade between colors
        final index = (t * colors.length).floor() % colors.length;
        final nextIndex = (index + 1) % colors.length;
        final localT = (t * colors.length) - index;
        return Color.lerp(colors[index], colors[nextIndex], localT)!;

      case 'pulse':
        // Pulse brightness of current color
        final index = (t * colors.length * 2).floor() % colors.length;
        final localT = ((t * colors.length * 2) % 1);
        final pulseFactor = 0.5 + 0.5 * (localT < 0.5 ? localT * 2 : 2 - localT * 2);
        final baseColor = colors[index];
        return Color.fromARGB(
          baseColor.alpha,
          (baseColor.red * pulseFactor).clamp(0, 255).toInt(),
          (baseColor.green * pulseFactor).clamp(0, 255).toInt(),
          (baseColor.blue * pulseFactor).clamp(0, 255).toInt(),
        );

      case 'strobe':
        // Rapid on/off flashing
        final index = (t * colors.length).floor() % colors.length;
        final flash = (t * 20) % 1;
        return flash < 0.5 ? colors[index] : Colors.black;

      case 'bounce':
        // Bounce between two colors at ends
        final index = (t * colors.length).floor() % colors.length;
        final localT = (t * colors.length * 2) % 2;
        final bounceT = localT < 1 ? localT : 2 - localT;
        final baseColor = colors[index];
        final dimColor = Color.fromARGB(
          baseColor.alpha,
          (baseColor.red * 0.3).clamp(0, 255).toInt(),
          (baseColor.green * 0.3).clamp(0, 255).toInt(),
          (baseColor.blue * 0.3).clamp(0, 255).toInt(),
        );
        return Color.lerp(baseColor, dimColor, 1 - bounceT)!;

      case 'breathe':
        // Slow breathing fade in/out
        final index = (t * colors.length).floor() % colors.length;
        final localT = (t * colors.length) % 1;
        final breatheFactor = 0.2 + 0.8 * (0.5 + 0.5 * math.sin(localT * 2 * math.pi));
        final baseColor = colors[index];
        return Color.fromARGB(
          baseColor.alpha,
          (baseColor.red * breatheFactor).clamp(0, 255).toInt(),
          (baseColor.green * breatheFactor).clamp(0, 255).toInt(),
          (baseColor.blue * breatheFactor).clamp(0, 255).toInt(),
        );

      case 'blink':
        // Periodic blink (on/off)
        final index = (t * colors.length).floor() % colors.length;
        final blink = (t * 2) % 1;
        return blink < 0.7 ? colors[index] : Colors.black;

      case 'heartbeat':
        // Quick heartbeat-like pulse
        final index = (t * colors.length).floor() % colors.length;
        final localT = (t * colors.length) % 1;
        final beat = localT < 0.15 ? localT / 0.15 : (localT < 0.3 ? (0.15 - localT + 0.15) / 0.15 : 0);
        final pulseFactor = 1.0 - 0.5 * beat;
        final baseColor = colors[index];
        return Color.fromARGB(
          baseColor.alpha,
          (baseColor.red * pulseFactor).clamp(0, 255).toInt(),
          (baseColor.green * pulseFactor).clamp(0, 255).toInt(),
          (baseColor.blue * pulseFactor).clamp(0, 255).toInt(),
        );

      case 'sparkle':
        // Random sparkles on base color
        final index = (t * colors.length).floor() % colors.length;
        final baseColor = colors[index];
        final sparkle = math.sin((index * 0.1 + t * 20) * math.pi);
        if (sparkle > 0.7) {
          return Colors.white;
        }
        return baseColor;

      default:
        // Default to fade
        final index = (t * colors.length).floor() % colors.length;
        final nextIndex = (index + 1) % colors.length;
        final localT = (t * colors.length) - index;
        return Color.lerp(colors[index], colors[nextIndex], localT)!;
    }
  }

  Widget _buildRainbowWheel() {
    // Rainbow colors for the animation
    final rainbowColors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.cyan,
      Colors.blue,
      Colors.purple,
      Colors.pink,
    ];
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                // Calculate current rainbow color based on animation
                final t = _glowController.value;
                final index = (t * rainbowColors.length).floor() % rainbowColors.length;
                final nextIndex = (index + 1) % rainbowColors.length;
                final localT = (t * rainbowColors.length) - index;
                final glowColor = Color.lerp(rainbowColors[index], rainbowColors[nextIndex], localT)!;
                
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.8,
                      colors: [
                        glowColor.withOpacity(0.3),
                        glowColor.withOpacity(0.1),
                        const Color(0xFF0A0A0A),
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: glowColor.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: LEDRing3DViewer(
                      colors: rainbowColors,
                      glowColor: glowColor,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Rainbow Mode',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Drag to rotate • Pinch to zoom',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.palette, size: 100, color: Colors.grey.shade700),
          const SizedBox(height: 24),
          Text(
            'No colours added',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add colours',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

Widget _build3DVisualization() {
  final currentColor = colourPattern.isEmpty ? Colors.grey : _getGlowColor();

  return Container(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        // 3D LED Ring Model
        Expanded(
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              final glowColor = _getGlowColor();
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [
                      glowColor.withOpacity(0.2),
                      glowColor.withOpacity(0.05),
                      const Color(0xFF0A0A0A),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: glowColor.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withOpacity(0.3),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      // 3D LED Ring Viewer
                      LEDRing3DViewer(
                        colors: colourPattern,
                        glowColor: glowColor,
                      ),
                      // Color overlay for glow effect
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.center,
                                radius: 0.6,
                                colors: [
                                  glowColor.withOpacity(0.0),
                                  glowColor.withOpacity(0.1),
                                  glowColor.withOpacity(0.2),
                                ],
                                stops: const [0.3, 0.6, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Color pattern indicator below view
        const SizedBox(height: 12),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: currentColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: colourPattern.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showColorOptions(index);
                },
                child: Container(
                  width: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.3),
                      radius: 1.2,
                      colors: [
                        Color.lerp(colourPattern[index], Colors.white, 0.3)!,
                        colourPattern[index],
                        Color.lerp(colourPattern[index], Colors.black, 0.3)!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colourPattern[index].withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Helper text
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Drag to rotate • Pinch to zoom • Tap colors to edit',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

  void _showColorOptions(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Color ${index + 1}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Color'),
              onTap: () {
                Navigator.pop(context);
                _showColourPicker(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Remove Color'),
              onTap: () {
                Navigator.pop(context);
                HapticFeedback.lightImpact();
                setState(() {
                  colourPattern.removeAt(index);
                  widget.deviceState.updatePatternColours(colourPattern);
                });
                _showSnackBar('Colour removed', Icons.delete);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransitionSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Transition Effect',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _transitions.length,
              itemBuilder: (context, index) {
                final transition = _transitions[index];
                final isSelected = _selectedTransition == transition['id'];
                return Padding(
                  padding: EdgeInsets.only(right: index < _transitions.length - 1 ? 8 : 0),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedTransition = transition['id']!);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFF8C00).withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFF8C00)
                              : Colors.grey.shade700,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          transition['name']!,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFFF8C00)
                                : Colors.grey.shade400,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: colourPattern.isEmpty
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        colourPattern.clear();
                        widget.deviceState.updatePatternColours(colourPattern);
                      });
                      _showSnackBar('Pattern cleared', Icons.delete_sweep);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.grey,
                disabledBackgroundColor: const Color(0xFF1A1A1A).withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colourPattern.isEmpty
                        ? Colors.grey.shade800
                        : Colors.grey.shade700,
                    width: 2,
                  ),
                ),
              ),
              child: const Icon(Icons.delete_sweep),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: colourPattern.isEmpty
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      _savePattern();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: const Color(0xFFFF8C00),
                disabledBackgroundColor: const Color(0xFF1A1A1A).withOpacity(0.5),
                disabledForegroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colourPattern.isEmpty
                        ? Colors.grey.shade800
                        : const Color(0xFFFF8C00),
                    width: 2,
                  ),
                ),
              ),
              child: const Icon(Icons.save),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _selectedTransition == 'color_wheel'
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _editingColorIndex = -1; // -1 means adding new color
                        _pickerColour = Colors.deepPurple;
                        _isColourPickerVisible = true;
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: const Color(0xFFFF8C00),
                disabledBackgroundColor: const Color(0xFF1A1A1A).withOpacity(0.5),
                disabledForegroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _selectedTransition == 'color_wheel'
                        ? Colors.grey.shade800
                        : const Color(0xFFFF8C00),
                    width: 2,
                  ),
                ),
              ),
              child: const Icon(Icons.add),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: (colourPattern.isEmpty && _selectedTransition != 'color_wheel')
                  ? null
                  : () async {
                      HapticFeedback.mediumImpact();
                      await _sendPattern();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFFF8C00).withOpacity(0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send),
                  SizedBox(width: 8),
                  Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColourPickerOverlay() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      bottom: _isColourPickerVisible ? 0 : -MediaQuery.of(context).size.height,
      left: 0,
      right: 0,
      height: MediaQuery.of(context).size.height * 0.6,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pick a Colour',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isColourPickerVisible = false;
                      });
                    },
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: ColorPicker(
                  pickerColor: _pickerColour,
                  onColorChanged: (color) {
                    setState(() {
                      _pickerColour = color;
                    });
                  },
                  pickerAreaHeightPercent: 0.65,
                  displayThumbColor: true,
                  enableAlpha: false,
                  labelTypes: const [],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (_editingColorIndex >= 0) {
                      // Editing existing color
                      colourPattern[_editingColorIndex] = _pickerColour;
                      _showSnackBar('Colour updated', Icons.check_circle);
                    } else {
                      // Adding new color
                      colourPattern.add(_pickerColour);
                      _showSnackBar('Colour added', Icons.check_circle);
                    }
                    widget.deviceState.updatePatternColours(colourPattern);
                    _isColourPickerVisible = false;
                    _editingColorIndex = -1;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _editingColorIndex >= 0 ? 'Update Colour' : 'Add Colour',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showColourPicker(int index) {
    setState(() {
      _editingColorIndex = index;
      _pickerColour = colourPattern[index];
      _isColourPickerVisible = true;
    });
  }

  Future<void> _sendPattern() async {
    if (!widget.deviceState.isConnected) {
      _showSnackBar('Not connected to device', Icons.warning_amber);
      return;
    }

    if (colourPattern.isEmpty && _selectedTransition != 'color_wheel') {
      _showSnackBar('Add colours first', Icons.info);
      return;
    }

    try {
      final Map<String, dynamic> patternData;

      if (_selectedTransition == 'color_wheel') {
        // Rainbow mode: send white color with color_wheel transition
        patternData = {
          'pattern': [
            {'r': 255, 'g': 255, 'b': 255}
          ],
          'count': 1,
          'transition': 'color_wheel',
        };
      } else {
        // Normal mode: send color pattern
        patternData = {
          'pattern': colourPattern
              .map((c) => {
                    'r': c.red,
                    'g': c.green,
                    'b': c.blue,
                  })
              .toList(),
          'count': colourPattern.length,
          'transition': _selectedTransition,
        };
      }

      await widget.deviceState.sendPattern(patternData);
      _showSnackBar(
        _selectedTransition == 'color_wheel' ? 'Rainbow mode activated!' : 'Pattern sent successfully!',
        _selectedTransition == 'color_wheel' ? Icons.gradient : Icons.check_circle,
      );
    } catch (e) {
      _showSnackBar('Failed to send pattern', Icons.error);
    }
  }

  void _showSnackBar(String message, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 180),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _savePattern() async {
    final TextEditingController nameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Save Pattern', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Pattern name',
            hintStyle: TextStyle(color: Colors.grey.shade600),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade700),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF8C00)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C00),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      final pattern = SavedPattern(
        name: nameController.text,
        colors: List.from(colourPattern),
        transition: _selectedTransition,
        savedAt: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      final patterns = prefs.getStringList('saved_patterns') ?? [];
      patterns.add(jsonEncode(pattern.toJson()));
      await prefs.setStringList('saved_patterns', patterns);

      _showSnackBar('Pattern saved!', Icons.save);
    }
  }
}

// Library Screen
class LibraryScreen extends StatefulWidget {
  final DeviceState deviceState;

  const LibraryScreen({super.key, required this.deviceState});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool _isDownloading = false;
  List<SavedPattern> _savedPatterns = [];
  late AnimationController _glowController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadPatterns();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadPatterns() async {
    final prefs = await SharedPreferences.getInstance();
    final patternsJson = prefs.getStringList('saved_patterns') ?? [];

    setState(() {
      _savedPatterns = patternsJson
          .map((json) => SavedPattern.fromJson(jsonDecode(json)))
          .toList();
    });
  }

  Future<void> _downloadFromChip() async {
    if (!widget.deviceState.isConnected) {
      _showSnackBar('Not connected to device', Icons.warning_amber);
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      // Send GET_PATTERN command
      await widget.deviceState.port?.write(Uint8List.fromList(utf8.encode('GET_PATTERN\n')));

      // Wait for response
      await Future.delayed(const Duration(milliseconds: 1500));

      setState(() {
        _isDownloading = false;
      });

      if (widget.deviceState.currentChipPattern != null) {
        setState(() {}); // Trigger rebuild to show the chip pattern
        _showSnackBar('Pattern retrieved from chip', Icons.check_circle);
      } else {
        _showSnackBar('No pattern found on chip', Icons.info_outline);
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      _showSnackBar('Failed to retrieve pattern', Icons.error_outline);
    }
  }

  Widget _buildChipPatternCard(SavedPattern pattern) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowProgress = _glowController.value;
        final glowOpacity = 0.3 + (0.2 * (glowProgress - 0.5).abs() * 2);

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _sendPattern(pattern);
          },
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8C00).withOpacity(glowOpacity),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFF8C00),
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFF8C00),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Current Pattern',
                          style: TextStyle(
                            color: Color(0xFFFF8C00),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        color: const Color(0xFF2A2A2A),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            onTap: () => _copyPatternToCreate(pattern),
                            child: const Row(
                              children: [
                                Icon(Icons.copy, color: Colors.white, size: 20),
                                SizedBox(width: 12),
                                Text('Copy to Create', style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 60,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: pattern.transition == 'color_wheel'
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Colors.red,
                                Colors.orange,
                                Colors.yellow,
                                Colors.green,
                                Colors.cyan,
                                Colors.blue,
                                Colors.purple,
                                Colors.pink,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 2,
                            ),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: pattern.colors.length,
                          itemBuilder: (context, index) {
                            return Container(
                              width: 50,
                              height: 50,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: pattern.colors[index],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 2,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const Text(
                    'Pattern Library',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: widget.deviceState,
                    builder: (context, _) {
                      return ElevatedButton.icon(
                        onPressed: widget.deviceState.isConnected && !_isDownloading
                            ? () {
                                HapticFeedback.lightImpact();
                                _downloadFromChip();
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFFF8C00).withOpacity(0.3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download, size: 20),
                        label: const Text('From Chip', style: TextStyle(fontSize: 13)),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isDownloading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFFF8C00)),
                          SizedBox(height: 16),
                          Text(
                            'Reading pattern from chip...',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPatterns,
                      color: const Color(0xFFFF8C00),
                      backgroundColor: const Color(0xFF1A1A1A),
                      child: _buildPatternsList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatternsList() {
    if (_savedPatterns.isEmpty && widget.deviceState.currentChipPattern == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 100, color: Colors.grey.shade700),
            const SizedBox(height: 24),
            Text(
              'No saved patterns',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create and save patterns to see them here',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        if (widget.deviceState.currentChipPattern != null) ...[
          _buildChipPatternCard(widget.deviceState.currentChipPattern!),
          if (_savedPatterns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Saved Patterns',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
        ..._savedPatterns.map((pattern) => _buildPatternCard(pattern)),
      ],
    );
  }

  Widget _buildPatternCard(SavedPattern pattern) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _sendPattern(pattern);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.grey.shade800,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pattern.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${pattern.colors.length} colours • ${pattern.transition}',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    color: const Color(0xFF2A2A2A),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: () => _sendPattern(pattern),
                        child: const Row(
                          children: [
                            Icon(Icons.send, color: Colors.white, size: 20),
                            SizedBox(width: 12),
                            Text('Send to Device', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        onTap: () => _copyPatternToCreate(pattern),
                        child: const Row(
                          children: [
                            Icon(Icons.copy, color: Colors.white, size: 20),
                            SizedBox(width: 12),
                            Text('Copy to Create', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        onTap: () => _exportPattern(pattern),
                        child: const Row(
                          children: [
                            Icon(Icons.share, color: Colors.white, size: 20),
                            SizedBox(width: 12),
                            Text('Export', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        onTap: () => _deletePattern(pattern),
                        child: const Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 20),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              height: 60,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: pattern.transition == 'color_wheel'
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Colors.red,
                            Colors.orange,
                            Colors.yellow,
                            Colors.green,
                            Colors.cyan,
                            Colors.blue,
                            Colors.purple,
                            Colors.pink,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: pattern.colors.length,
                      itemBuilder: (context, index) {
                        return Container(
                          width: 50,
                          height: 50,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: pattern.colors[index],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 2,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPattern(SavedPattern pattern) async {
    if (!widget.deviceState.isConnected) {
      _showSnackBar('Not connected to device', Icons.warning_amber);
      return;
    }

    try {
      final patternData = {
        'pattern': pattern.colors
            .map((c) => {
                  'r': c.red,
                  'g': c.green,
                  'b': c.blue,
                })
            .toList(),
        'count': pattern.colors.length,
        'transition': pattern.transition,
      };

      await widget.deviceState.sendPattern(patternData);
      _showSnackBar('Pattern sent to device!', Icons.check_circle);
    } catch (e) {
      _showSnackBar('Failed to send pattern', Icons.error);
    }
  }

  void _copyPatternToCreate(SavedPattern pattern) {
    widget.deviceState.setPatternToCopy(pattern);
    _showSnackBar('Pattern ready to load in Create tab', Icons.info);
  }

  Future<void> _exportPattern(SavedPattern pattern) async {
    try {
      final jsonString = jsonEncode(pattern.toJson());
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${pattern.name}.huj');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'HUJ Pattern: ${pattern.name}',
      );

      _showSnackBar('Pattern exported', Icons.share);
    } catch (e) {
      _showSnackBar('Failed to export pattern', Icons.error);
    }
  }

  Future<void> _deletePattern(SavedPattern pattern) async {
    final prefs = await SharedPreferences.getInstance();
    final patterns = prefs.getStringList('saved_patterns') ?? [];
    patterns.removeWhere((json) {
      final p = SavedPattern.fromJson(jsonDecode(json));
      return p.name == pattern.name && p.savedAt == pattern.savedAt;
    });
    await prefs.setStringList('saved_patterns', patterns);
    await _loadPatterns();
    _showSnackBar('Pattern deleted', Icons.delete);
  }

  void _showSnackBar(String message, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 180),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
