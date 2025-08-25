import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'cookie_manager.dart'; // Import the new manager

class USCISWebView extends StatefulWidget {
  final String caseNumber;
  final bool showUI; // True if we need to show WebView for CAPTCHA

  const USCISWebView({Key? key, required this.caseNumber, this.showUI = false})
      : super(key: key);

  @override
  _USCISWebViewState createState() => _USCISWebViewState();
}

class _USCISWebViewState extends State<USCISWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _requireCaptcha = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('CaseChannel', onMessageReceived: (message) {
        final status = message.message.trim();

        if (status.isEmpty || status.startsWith('Verifique el Estatus de su Caso')) {
          // CAPTCHA required
          if (widget.showUI) {
            setState(() => _requireCaptcha = true);
          } else {
            Navigator.pop(context, '__CAPTCHA__');
          }
        } else {
          Navigator.pop(context, status);
        }
      })
      ..loadRequest(Uri.parse('https://egov.uscis.gov/es'))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            // After any page finishes loading, save the cookies
            final cookies = await _controller.runJavaScriptReturningResult('document.cookie');
            await CookieManager().saveCookies(cookies?.toString());
            
            // ... your existing onPageFinished logic ...
            await _injectJavaScript();
            if (widget.showUI) setState(() => _loading = false);
          },
          onPageStarted: (String url) {
            // Reset loading state when a new page starts loading
            if (widget.showUI && mounted) {
              setState(() => _loading = true);
            }
          },
          onWebResourceError: (WebResourceError error) {
            // Handle errors gracefully
            if (widget.showUI && mounted) {
              setState(() => _loading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error loading page: ${error.description}')),
              );
            }
          },
        ),
      );
  }

  @override
  void dispose() {
    // Make sure to properly dispose the controller
    super.dispose();
  }

  Future<void> _injectJavaScript() async {
    await _controller.runJavaScript('''
      (function() {
        // Remove any existing button first to avoid duplicates
        const existingBtn = document.getElementById('done-btn');
        if (existingBtn) existingBtn.remove();
        
        // Add "Listo" button immediately with improved styling
        const listoBtn = document.createElement('button');
        listoBtn.id = 'done-btn';
        listoBtn.innerText = 'Listo';
        listoBtn.style.position = 'fixed';
        listoBtn.style.top = '10px';
        listoBtn.style.right = '10px';
        listoBtn.style.padding = '10px 16px';
        listoBtn.style.background = '#0071bc';
        listoBtn.style.color = 'white';
        listoBtn.style.border = '2px solid white';
        listoBtn.style.borderRadius = '4px';
        listoBtn.style.zIndex = '999999';
        listoBtn.style.fontWeight = 'bold';
        listoBtn.style.fontSize = '16px';
        listoBtn.style.boxShadow = '0 2px 5px rgba(0,0,0,0.3)';
        
        // Direct click function - simpler and more reliable
        listoBtn.onclick = function() {
          try {
            const statusDiv = document.querySelector('.conditionalLanding');
            let statusText = statusDiv ? statusDiv.innerText.trim() : '';
            
            if (!statusText || statusText === '') {
              statusText = 'Toque para ver estado';
            }
            
            console.log("Listo button clicked, sending status");
            window.CaseChannel.postMessage(statusText);
          } catch (e) {
            console.error("Error in Listo button: " + e);
            window.CaseChannel.postMessage('Toque para ver estado');
          }
        };
        
        // Add to document body with timeout to ensure DOM is ready
        setTimeout(function() {
          document.body.appendChild(listoBtn);
          console.log("Listo button added");
        }, 500);
        
        // Handle the case input form if it exists
        const input = document.querySelector('input[name="receipt_number"]');
        const button = document.querySelector('button[name="initCaseSearch"]');

        if (input && button) {
          // Properly set React-controlled input
          const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
          nativeInputValueSetter.call(input, '${widget.caseNumber}');
          input.dispatchEvent(new Event('input', { bubbles: true }));

          // Enable and click automatically
          button.removeAttribute('disabled');
          button.click();

          // Observe changes in .conditionalLanding
          const observer = new MutationObserver(() => {
            const statusDiv = document.querySelector('.conditionalLanding');
            let statusText = statusDiv ? statusDiv.innerText.trim() : '';
            
            if (statusText) {
              // If we have content in statusDiv, process and send it
              if (!statusText.includes('Verifique el Estatus de su Caso')) {
                console.log("Found case status, auto-closing");
                CaseChannel.postMessage(statusText);
                observer.disconnect();
              }
            }
          });
          
          const statusDiv = document.querySelector('.conditionalLanding');
          if (statusDiv) observer.observe(statusDiv, { childList: true, subtree: true });
          
          // Set a timeout to auto-close if nothing happens
          setTimeout(function() {
            const statusDiv = document.querySelector('.conditionalLanding');
            let statusText = statusDiv ? statusDiv.innerText.trim() : '';
            
            if (statusText && !statusText.includes('Verifique el Estatus de su Caso')) {
              console.log("Timeout reached, found status");
              CaseChannel.postMessage(statusText);
            }
          }, 10000);
        }
      })();
    ''');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showUI) return const SizedBox.shrink(); // Headless WebView

    return WillPopScope(
      onWillPop: () async => true, // Allow users to go back
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verificar Caso'),
          automaticallyImplyLeading: true,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
