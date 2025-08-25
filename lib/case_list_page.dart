import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'uscis_webview.dart';
import 'case_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_svg/flutter_svg.dart'; 
import 'eoir_webview.dart';

class CaseListPage extends StatefulWidget {
  final CaseService service;
  const CaseListPage({Key? key, required this.service}) : super(key: key);

  @override
  _CaseListPageState createState() => _CaseListPageState();
}

class _CaseListPageState extends State<CaseListPage> {
  // Constants
  static const String _pendingStatus = 'Toque para ver estado';
  
  // State variables
  Map<String, Map<String, String>> statuses = {}; // {caseNumber: {'short': '', 'full': '', 'name': ''}}
  List<String> cases = [];
  bool _isFetching = false;
  String _privacyPolicyText = '';
  String _termsOfServiceText = '';
  String _instructionsText = '';  // Add this line

  @override
  void initState() {
    super.initState();
    _loadCasesFromPrefs();
    _loadTextAssets();
  }

  // ---------- Data Loading & Persistence ----------
  
  Future<void> _loadCasesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCases = prefs.getStringList('cases') ?? [];
    
    // Load statuses for each case
    final Map<String, Map<String, String>> loadedStatuses = {};
    for (final caseNumber in savedCases) {
      final statusJson = prefs.getString('status_$caseNumber');
      if (statusJson != null) {
        try {
          final Map<String, dynamic> decodedMap = jsonDecode(statusJson);
          final Map<String, String> stringMap = decodedMap.map(
            (key, value) => MapEntry(key, value?.toString() ?? '')
          );
          // Ensure type is always set
          if (!stringMap.containsKey('type')) {
            stringMap['type'] = _isValidEOIRNumber(caseNumber) ? 'eoir' : 'uscis';
          }
          loadedStatuses[caseNumber] = stringMap;
        } catch (e) {
          loadedStatuses[caseNumber] = {
            'short': _pendingStatus,
            'full': '',
            'name': '',
            'type': _isValidEOIRNumber(caseNumber) ? 'eoir' : 'uscis'
          };
        }
      } else {
        loadedStatuses[caseNumber] = {
          'short': _pendingStatus,
          'full': '',
          'name': '',
          'type': _isValidEOIRNumber(caseNumber) ? 'eoir' : 'uscis'
        };
      }
    }
    
    setState(() {
      cases = savedCases;
      statuses = loadedStatuses;
    });
    
    await _fetchAllCasesSequentially(savedCases);
  }

  Future<void> _saveCasesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('cases', cases);
    
    final Map<String, String> serializedStatuses = {};
    statuses.forEach((caseNumber, statusMap) {
      serializedStatuses[caseNumber] = jsonEncode(statusMap);
    });
    
    for (final entry in serializedStatuses.entries) {
      await prefs.setString('status_${entry.key}', entry.value);
    }
  }

  // ---------- Case Status Management ----------

  Future<void> _fetchAllCasesSequentially(List<String> caseList) async {
    if (_isFetching) return;
    setState(() => _isFetching = true);

    // Create a copy of the list to prevent concurrent modification error
    final casesToProcess = List<String>.from(caseList);

    for (var caseNumber in casesToProcess) {
      if (!mounted) break;
      await _fetchCaseStatus(caseNumber);
    }

    if (mounted) {
      setState(() => _isFetching = false);
    }
  }

  Future<void> _fetchCaseStatus(String caseNumber) async {
    try {
      String fullText = await widget.service.fetchCaseStatus(caseNumber);
      String shortText = fullText.split('\n')[0];

      if (mounted) {
        setState(() {
          final currentName = statuses[caseNumber]?['name'] ?? '';
          final currentType = statuses[caseNumber]?['type'] ?? 
              (_isValidEOIRNumber(caseNumber) ? 'eoir' : 'uscis');
          
          if (fullText.isEmpty || fullText.contains("Verifique el Estatus de su Caso")) {
            statuses[caseNumber] = {
              'short': _pendingStatus, 
              'full': '',
              'name': currentName,
              'type': currentType // Preserve type
            };
          } else {
            statuses[caseNumber] = {
              'short': shortText, 
              'full': fullText, 
              'name': currentName,
              'type': currentType // Preserve type
            };
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final currentName = statuses[caseNumber]?['name'] ?? '';
          final currentType = statuses[caseNumber]?['type'] ?? 
              (_isValidEOIRNumber(caseNumber) ? 'eoir' : 'uscis');
          
          statuses[caseNumber] = {
            'short': _pendingStatus, 
            'full': '', 
            'name': currentName,
            'type': currentType // Preserve type
          };
        });
      }
    }
  }

  // ---------- User Interactions ----------

  void _addCase() async {
    String receiptNumber = '';
    String caseName = '';

    bool? shouldAdd = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agregar Caso'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => receiptNumber = value,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Número de Recibo',
                  hintText: 'Ejemplo: IOE0123456789'
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => caseName = value,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Caso',
                  hintText: 'Ejemplo: Permiso de trabajo'
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text('Cancelar')
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              child: const Text('Agregar')
            ),
          ],
        );
      },
    );

    if (shouldAdd == true && receiptNumber.isNotEmpty) {
      receiptNumber = receiptNumber.toUpperCase();
      
      setState(() => cases.add(receiptNumber));
      statuses[receiptNumber] = {
        'short': _pendingStatus,
        'full': '',
        'name': caseName
      };
      _saveCasesToPrefs();
      _fetchCaseStatus(receiptNumber);
    }
  }

  void _deleteCase(String caseNumber) async {
    await widget.service.deleteCase(caseNumber);
    setState(() {
      cases.remove(caseNumber);
      statuses.remove(caseNumber);
    });
    _saveCasesToPrefs();
  }

  void _openCase(String caseNumber) async {
    final statusMap = statuses[caseNumber];
    final fullText = statusMap?['full'] ?? '';
    final shortText = statusMap?['short'] ?? _pendingStatus;
    final caseType = statusMap?['type'] ?? 'uscis'; // Default to USCIS if not specified

    if (shortText.contains(_pendingStatus) || shortText.contains('Error')) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => caseType == 'eoir' 
              ? EOIRWebView(alienNumber: caseNumber, showUI: true)
              : USCISWebView(caseNumber: caseNumber, showUI: true),
        ),
      );

      if (result != null && result.toString().isNotEmpty && result != '__CAPTCHA__') {
        final full = result.toString();
        String short;
        
        // For EOIR cases, handle the "No hay información" message
        if (caseType == 'eoir' && full.contains('No hay información de caso')) {
          short = 'No hay información de caso';
        } else {
          short = full.split('\n')[0];
        }
        
        final currentName = statuses[caseNumber]?['name'] ?? '';
        
        if (mounted) {
          setState(() {
            statuses[caseNumber] = {
              'short': short, 
              'full': full, 
              'name': currentName,
              'type': caseType
            };
          });
        }

        _saveCasesToPrefs();
        _showFullDialog(caseNumber, full);
      }
    } else {
      _showFullDialog(caseNumber, fullText);
    }
  }

  void _showFullDialog(String caseNumber, String fullText) {
    final name = statuses[caseNumber]?['name'] ?? '';
    final title = name.isNotEmpty ? "$name ($caseNumber)" : caseNumber;
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(fullText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cerrar')
          ),
        ],
      ),
    );
  }

  // ---------- UI Building ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Casos'),
        actions: [
          IconButton(
            icon: Image.asset(
              'assets/images/about_logo.png',
              width: 24,
              height: 24,
            ),
            onPressed: _showAboutDialog,
            tooltip: 'Acerca de',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh, // Use the new refresh method
        child: ListView.builder(
          itemCount: cases.length,
          itemBuilder: (context, index) {
            final c = cases[index];
            final status = statuses[c]?['short'] ?? _pendingStatus;
            final name = statuses[c]?['name'] ?? '';
            final type = statuses[c]?['type'] ?? 
                (_isValidEOIRNumber(c) ? 'eoir' : 'uscis');
            
            return Dismissible(
              key: Key(c),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => _deleteCase(c),
              child: ListTile(
                leading: type == 'eoir' 
                  ? SizedBox(
                      width: 32,
                      height: 32,
                      child: SvgPicture.asset(
                        'assets/images/eoir_logo.svg',
                        fit: BoxFit.contain,
                      ),
                    )
                  : SizedBox(
                      width: 32, 
                      height: 32,
                      child: Image.asset(
                        'assets/images/uscis_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                title: Text(name.isNotEmpty ? name : c.toUpperCase()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty) Text(c.toUpperCase(), style: TextStyle(fontSize: 12)),
                    Text(status),
                  ],
                ),
                onTap: () => _openCase(c),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCaseOptions,
        tooltip: 'Agregar caso',
        child: Image.asset(
          'assets/images/add_logo.png',
          width: 24,
          height: 24,
        ),
      ),
    );
  }
  
  // Show options dialog for case type selection
  void _showAddCaseOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Tipo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Image.asset(
                'assets/images/uscis_logo.png',
                width: 32,
                height: 32,
              ),
              title: const Text('USCIS'),
              subtitle: const Text('Casos de inmigración'),
              onTap: () {
                Navigator.pop(context);
                _addUSCISCase();
              },
            ),
            ListTile(
              leading: SvgPicture.asset(
                'assets/images/eoir_logo.svg',
                width: 32,
                height: 32,
              ),
              title: const Text('EOIR'),
              subtitle: const Text('Casos de corte'),
              onTap: () {
                Navigator.pop(context);
                _addEOIRCase();
              },
            ),
          ],
        ),
      ),
    );
  }
  
  // Add USCIS case (original flow)
  void _addUSCISCase() async {
    String receiptNumber = '';
    String caseName = '';

    bool? shouldAdd = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agregar Caso USCIS'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => receiptNumber = value,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Número de Recibo',
                  hintText: 'Ejemplo: IOE0123456789'
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => caseName = value,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Caso',
                  hintText: 'Ejemplo: Permiso de trabajo'
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text('Cancelar')
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              child: const Text('Agregar')
            ),
          ],
        );
      },
    );

    if (shouldAdd == true && receiptNumber.isNotEmpty) {
      receiptNumber = receiptNumber.toUpperCase().trim();
      
      // Warn if this looks like an EOIR number
      if (_isValidEOIRNumber(receiptNumber)) {
        bool? useAnyway = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Es esto un número de alien?'),
            content: const Text('Este parece ser un número de alien (EOIR), no un número de caso USCIS. ¿Desea agregarlo como caso USCIS de todas formas?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Agregar como USCIS'),
              ),
            ],
          ),
        );
        if (useAnyway != true) return;
      }
      
      setState(() => cases.add(receiptNumber));
      statuses[receiptNumber] = {
        'short': _pendingStatus,
        'full': '',
        'name': caseName,
        'type': 'uscis'  // Explicitly set USCIS type
      };
      _saveCasesToPrefs();
      _fetchCaseStatus(receiptNumber);
    }
  }
  
  // Add EOIR case (new flow)
  void _addEOIRCase() async {
    String alienNumber = '';
    String alienName = '';

    bool? shouldAdd = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agregar Caso EOIR'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => alienName = value,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Alien',
                  hintText: 'Ejemplo: Juan Pérez'
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => alienNumber = value,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Número de Alien',
                  hintText: 'Ejemplo: A123456789'
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text('Cancelar')
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              child: const Text('Agregar')
            ),
          ],
        );
      },
    );

    if (shouldAdd == true && alienNumber.isNotEmpty) {
      // Format the alien number to ensure it starts with 'A' and contains only the 9 digits
      alienNumber = alienNumber.toUpperCase().trim();
      if (!alienNumber.startsWith('A')) {
        alienNumber = 'A$alienNumber';
      }
      
      // Extract just the numeric part
      final numericPart = alienNumber.substring(1).replaceAll(RegExp(r'\D'), '');
      
      // Validate that we have exactly 9 digits
      if (numericPart.length != 9) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El número de alien debe tener exactamente 9 dígitos.')),
        );
        return;
      }
      
      // Reconstruct the valid alien number
      alienNumber = 'A$numericPart';
      
      setState(() => cases.add(alienNumber));
      statuses[alienNumber] = {
        'short': _pendingStatus,
        'full': '',
        'name': alienName,
        'type': 'eoir'  // Mark as EOIR case type
      };
      _saveCasesToPrefs();
    }
  }
  
  // Add validation utility methods
  bool _isValidEOIRNumber(String number) {
    // EOIR numbers must be 'A' followed by exactly 9 digits
    final cleanNumber = number.toUpperCase().trim();
    final regex = RegExp(r'^A\d{9}$');
    return regex.hasMatch(cleanNumber);
  }
  
  bool _isValidUSCISNumber(String number) {
    // USCIS numbers typically have 3 letters followed by 10 digits, or other formats
    // This is a basic check to avoid mixing with EOIR numbers
    final cleanNumber = number.toUpperCase().trim();
    return !cleanNumber.startsWith('A') || cleanNumber.length != 10;
  }

  // Updated refresh method to handle both case types
  Future<void> onRefresh() async {
    bool cancelRefresh = false;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Actualizando Casos'),
        content: const Text('Procesando estados de casos...'),
        actions: [
          TextButton(
            onPressed: () {
              cancelRefresh = true;
              Navigator.of(context).pop();
            },
            child: const Text('Listo'),
          ),
        ],
      ),
    );
    
    final casesToRefresh = cases
        .where((c) =>
            (statuses[c]?['short'] ?? _pendingStatus).contains(_pendingStatus) ||
            (statuses[c]?['short'] ?? _pendingStatus).contains('Error'))
        .toList();

    for (var caseNumber in casesToRefresh) {
      if (cancelRefresh || !mounted) break;

      // Determine the case type
      final caseType = statuses[caseNumber]?['type'] ?? 
          (_isValidEOIRNumber(caseNumber) ? 'eoir' : 'uscis');
      
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => caseType == 'eoir'
              ? EOIRWebView(alienNumber: caseNumber, showUI: true)
              : USCISWebView(caseNumber: caseNumber, showUI: true),
        ),
      );

      if (result != null && result.toString().isNotEmpty && result != '__CAPTCHA__') {
        if (!mounted) break;
        
        final full = result.toString();
        String short;
        
        // For EOIR cases, handle the "No hay información" message
        if (caseType == 'eoir' && full.contains('No hay información de caso')) {
          short = 'No hay información de caso';
        } else {
          short = full.split('\n')[0];
        }
        
        setState(() {
          final currentName = statuses[caseNumber]?['name'] ?? '';
          statuses[caseNumber] = {
            'short': short, 
            'full': full, 
            'name': currentName,
            'type': caseType // Preserve case type
          };
        });
        await Future.delayed(const Duration(seconds: 2));
        _saveCasesToPrefs(); // Save after each successful update
      }
      
      if (cancelRefresh) break;
    }
    
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
  
  // Show the About dialog with privacy policy and terms
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 3,  // Changed from 2 to 3
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Acerca de la Aplicación',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const TabBar(
                  tabs: [
                    Tab(text: 'Instrucciones'),  // New tab first
                    Tab(text: 'Privacidad'),
                    Tab(text: 'Términos'),
                  ],
                  labelColor: Colors.blue,
                  unselectedLabelColor: Colors.grey,
                  isScrollable: true,  // Allow scrolling if tabs are too wide
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.only(top: 16),
                    child: TabBarView(
                      children: [
                        // Instructions (new tab)
                        SingleChildScrollView(
                          child: Text(
                            _instructionsText,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        // Privacy Policy
                        SingleChildScrollView(
                          child: Text(
                            _privacyPolicyText,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        // Terms of Service
                        SingleChildScrollView(
                          child: Text(
                            _termsOfServiceText,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'App Hecha Por Francisco Pino',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Add this method to load text from assets
  Future<void> _loadTextAssets() async {
    _privacyPolicyText = await rootBundle.loadString('assets/texts/privacy_policy.txt');
    _termsOfServiceText = await rootBundle.loadString('assets/texts/terms_of_service.txt');
    _instructionsText = await rootBundle.loadString('assets/texts/instructions.txt');  // Add this line
  }
}