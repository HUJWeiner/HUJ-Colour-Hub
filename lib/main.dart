import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:usb_serial/usb_serial.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Color Pattern Creator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const ColorPatternScreen(),
    );
  }
}

class ColorPatternScreen extends StatefulWidget {
  const ColorPatternScreen({super.key});

  @override
  State<ColorPatternScreen> createState() => _ColorPatternScreenState();
}

class _ColorPatternScreenState extends State<ColorPatternScreen>
    with SingleTickerProviderStateMixin {
  List<Color> colorPattern = [];
  UsbPort? _port;
  UsbDevice? _device;
  bool _isConnected = false;
  bool _isConnecting = false;
  late AnimationController _pulseController;
  
  // Transition types
  String _selectedTransition = 'instant';
  final List<Map<String, String>> _transitions = [
    {'id': 'instant', 'name': 'Instant', 'icon': '⚡'},
    {'id': 'fade', 'name': 'Fade', 'icon': '🌊'},
    {'id': 'wipe', 'name': 'Wipe', 'icon': '➡️'},
    {'id': 'pulse', 'name': 'Pulse', 'icon': '💫'},
  ];
  
  // USB monitoring
  StreamSubscription<UsbEvent>? _usbSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    // Listen for USB device events (attach/detach)
    _startUsbMonitoring();
  }
  
  void _startUsbMonitoring() {
    if (kIsWeb || !Platform.isAndroid) return;
    
    try {
      _usbSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
        if (event.event == UsbEvent.ACTION_USB_DETACHED) {
          if (_isConnected) {
            _handleAutoDisconnect();
          }
        }
      });
    } catch (e) {
      // USB monitoring not available
    }
  }
  
  void _handleAutoDisconnect() {
    setState(() {
      _isConnected = false;
      _port = null;
      _device = null;
    });
    _showSnackBar('RP2040 disconnected', Icons.usb_off);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _usbSubscription?.cancel();
    _port?.close();
    super.dispose();
  }

  Future<void> _checkUSBDevices() async {
    // USB Serial only works on Android
    if (kIsWeb || (!Platform.isAndroid)) {
      setState(() {
        _device = null;
      });
      return;
    }

    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      if (devices.isNotEmpty) {
        setState(() {
          _device = devices.first;
        });
      }
    } catch (e) {
      setState(() {
        _device = null;
      });
    }
  }

  Future<void> _connectToDevice() async {
    if (kIsWeb || (!Platform.isAndroid)) {
      _showSnackBar('USB Serial only works on Android devices', Icons.phone_android);
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      // Give the system time to enumerate devices
      await Future.delayed(const Duration(milliseconds: 300));
      
      List<UsbDevice> devices = await UsbSerial.listDevices();
      
      if (devices.isEmpty) {
        setState(() {
          _isConnecting = false;
        });
        _showSnackBar('No USB device found. Check OTG cable and RP2040.', Icons.error_outline);
        return;
      }

      // Try all available devices (in case multiple are connected)
      for (var device in devices) {
        try {
          _device = device;
          
          // Create port - this will trigger permission dialog if needed
          _port = await _device!.create();
          
          if (_port == null) continue;
          
          // Try to open the port
          bool opened = await _port!.open();

          if (opened) {
            // Give device time to stabilize after opening
            await Future.delayed(const Duration(milliseconds: 300));
            
            // Configure serial parameters
            try {
              await _port!.setPortParameters(
                115200,
                UsbPort.DATABITS_8,
                UsbPort.STOPBITS_1,
                UsbPort.PARITY_NONE,
              );
            } catch (e) {
              // Some devices don't support parameter setting, that's ok
            }

            setState(() {
              _isConnected = true;
              _isConnecting = false;
            });

            _showSnackBar('Connected to RP2040', Icons.check_circle);
            return; // Success!
          }
        } catch (e) {
          // Try next device
          continue;
        }
      }
      
      // If we get here, none of the devices worked
      setState(() {
        _isConnecting = false;
      });
      _showSnackBar('Could not connect to any USB device', Icons.error_outline);
      
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
      _showSnackBar('Connection error: Check USB permissions', Icons.error_outline);
    }
  }

  Future<void> _disconnectDevice() async {
    await _port?.close();
    setState(() {
      _isConnected = false;
      _port = null;
    });
    _showSnackBar('Disconnected', Icons.info_outline);
  }

  Future<void> _sendPattern() async {
    if (!_isConnected || _port == null) {
      _showSnackBar('Not connected to device', Icons.warning_amber);
      return;
    }

    Map<String, dynamic> patternData = {
      'pattern': colorPattern
          .map((color) => {
                'r': color.red,
                'g': color.green,
                'b': color.blue,
              })
          .toList(),
      'count': colorPattern.length,
      'transition': _selectedTransition,
    };

    String jsonString = jsonEncode(patternData);

    try {
      await _port!.write(Uint8List.fromList(utf8.encode('$jsonString\n')));
      _showSnackBar('Pattern sent with $_selectedTransition transition!', Icons.send);
    } catch (e) {
      _showSnackBar('Failed to send pattern', Icons.error_outline);
    }
  }

  void _addColor(Color color) {
    setState(() {
      colorPattern.add(color);
    });
  }

  void _showColorPicker() {
    Color pickerColor = colorPattern.isEmpty ? Colors.deepPurple : colorPattern.last;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Pick a Color',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ColorPicker(
                    pickerColor: pickerColor,
                    onColorChanged: (color) {
                      pickerColor = color;
                    },
                    pickerAreaHeightPercent: 0.8,
                    displayThumbColor: true,
                    enableAlpha: false,
                    labelTypes: const [],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        _addColor(pickerColor);
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Add Color'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _showDeviceInfo() async {
    if (kIsWeb || !Platform.isAndroid) {
      _showSnackBar('USB only works on Android', Icons.info);
      return;
    }

    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('USB Devices'),
          content: devices.isEmpty
              ? const Text('No USB devices detected.\n\nMake sure:\n• RP2040 is connected via OTG cable\n• Cable supports data (not charge-only)\n• External power is connected')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Found ${devices.length} device(s):'),
                      const SizedBox(height: 16),
                      ...devices.map((device) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Vendor ID: ${device.vid}'),
                            Text('Product ID: ${device.pid}'),
                            Text('Device ID: ${device.deviceId}'),
                            const Divider(),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnackBar('Error checking devices', Icons.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Color Pattern',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${colorPattern.length} colors',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: _showDeviceInfo,
                    tooltip: 'Device Info',
                  ),
                  const SizedBox(width: 8),
                  _buildConnectionButton(),
                ],
              ),
            ),

            // Color Grid
            Expanded(
              child: colorPattern.isEmpty
                  ? _buildEmptyState()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                        itemCount: colorPattern.length,
                        itemBuilder: (context, index) {
                          return _buildColorCard(index);
                        },
                      ),
                    ),
            ),

            // Bottom Action Bar
            _buildBottomActionBar(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showColorPicker,
        icon: const Icon(Icons.add),
        label: const Text('Add Color'),
        elevation: 2,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildConnectionButton() {
    if (_isConnecting) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Material(
      color: _isConnected
          ? Colors.green.withOpacity(0.2)
          : Theme.of(context).colorScheme.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _isConnected ? _disconnectDevice : _connectToDevice,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.usb,
                color: _isConnected
                    ? Colors.green
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _isConnected ? 'Connected' : 'Connect',
                style: TextStyle(
                  color: _isConnected
                      ? Colors.green
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.palette_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No colors yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add your first color',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorCard(int index) {
    return Card(
      elevation: 0,
      color: colorPattern[index],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${colorPattern[index].value.toRadixString(16).substring(2).toUpperCase()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          // Delete button in top right
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () {
                  setState(() {
                    colorPattern.removeAt(index);
                  });
                  _showSnackBar('Color removed', Icons.delete_outline);
                },
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Transition selector
          Row(
            children: [
              Icon(
                Icons.animation,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Transition:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _transitions.map((transition) {
                      final isSelected = _selectedTransition == transition['id'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Material(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedTransition = transition['id']!;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    transition['icon']!,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    transition['name']!,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.send,
                label: 'Send',
                onPressed: colorPattern.isEmpty ? null : _sendPattern,
                isPrimary: true,
              ),
              _buildActionButton(
                icon: Icons.clear_all,
                label: 'Clear',
                onPressed: colorPattern.isEmpty
                    ? null
                    : () {
                        setState(() {
                          colorPattern.clear();
                        });
                        _showSnackBar('Pattern cleared', Icons.delete_sweep);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: onPressed == null
              ? colorScheme.surfaceVariant
              : isPrimary
                  ? colorScheme.primaryContainer
                  : colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: onPressed == null
                        ? colorScheme.onSurfaceVariant.withOpacity(0.38)
                        : isPrimary
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: onPressed == null
                          ? colorScheme.onSurfaceVariant.withOpacity(0.38)
                          : isPrimary
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}