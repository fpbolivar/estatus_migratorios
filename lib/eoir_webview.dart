import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'cookie_manager.dart';

class EOIRWebView extends StatefulWidget {
  final String alienNumber;
  final bool showUI;

  const EOIRWebView({Key? key, required this.alienNumber, this.showUI = false})
      : super(key: key);

  @override
  _EOIRWebViewState createState() => _EOIRWebViewState();
}

class _EOIRWebViewState extends State<EOIRWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  String _alienNumberDigits = '';

  @override
  void initState() {
    super.initState();
    
    // Process alien number to remove the 'A' if present and ensure 9 digits
    _alienNumberDigits = widget.alienNumber.replaceAll('A', '').trim();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('EOIRChannel', onMessageReceived: (message) {
        final status = message.message.trim();
        
        if (status.isNotEmpty) {
          Navigator.pop(context, status);
        }
      })
      ..loadRequest(Uri.parse('https://acis.eoir.justice.gov/es/'))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            // After any page finishes loading, save the cookies
            final cookies = await _controller.runJavaScriptReturningResult('document.cookie');
            await CookieManager().saveCookies(cookies?.toString());
            
            // Process the page - first accept the terms, then fill the form
            await _processPage();
            if (widget.showUI) setState(() => _loading = false);
          },
          onPageStarted: (String url) {
            if (widget.showUI && mounted) {
              setState(() => _loading = true);
            }
          },
          onWebResourceError: (WebResourceError error) {
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

  Future<void> _processPage() async {
    await _controller.runJavaScript('''
      (function() {
        // Add "Listo" button immediately
        if (!document.getElementById('eoir-done-btn')) {
          const doneBtn = document.createElement('button');
          doneBtn.id = 'eoir-done-btn';
          doneBtn.innerText = 'Listo';
          doneBtn.style.position = 'fixed';
          doneBtn.style.top = '10px';
          doneBtn.style.right = '10px';
          doneBtn.style.padding = '10px 16px';
          doneBtn.style.background = '#0071bc';
          doneBtn.style.color = 'white';
          doneBtn.style.border = '2px solid white';
          doneBtn.style.borderRadius = '4px';
          doneBtn.style.zIndex = '999999';
          doneBtn.style.fontWeight = 'bold';
          doneBtn.style.fontSize = '16px';
          
          // Simple direct click handler with try-catch
          doneBtn.addEventListener('click', function() {
            try {
              console.log("Listo button clicked");
              if (window.location.href.includes('caseInformation')) {
                handleCaseFound();
              } else {
                handleCaseNotFound();
              }
            } catch (e) {
              console.error("Error in Listo button: " + e);
              EOIRChannel.postMessage('Toque para ver estado');
            }
          });
          
          document.body.appendChild(doneBtn);
        }
        
        // Function to handle when a case is found (redirected to case information page)
        function handleCaseFound() {
          console.log("Handling found case");
          try {
            // Try to find the grid container
            const gridContainer = document.querySelector(".grid.md\\\\:grid-cols-2.md\\\\:grid-rows-2");
            
            if (gridContainer) {
              // Extract all section information with better formatting
              let formattedOutput = "";
              
              // Get all sections (typically h-full elements)
              const sections = gridContainer.querySelectorAll(".h-full");
              
              if (sections && sections.length > 0) {
                sections.forEach((section, index) => {
                  // Find the section title (usually a bold element at the top)
                  const title = section.querySelector(".font-bold");
                  if (title) {
                    formattedOutput += title.textContent.trim().toUpperCase() + "\\n";
                    formattedOutput += "================================================\\n";
                  }
                  
                  // Extract all text content
                  const textContent = section.innerText
                    .replace(title ? title.textContent : "", "") // Remove the title from the content
                    .trim();
                    
                  formattedOutput += textContent + "\\n";
                  
                  // Add separator between sections (except after the last one)
                  if (index < sections.length - 1) {
                    formattedOutput += "\\n------------------------------------------------\\n\\n";
                  }
                });
                
                console.log("Sending formatted case information");
                EOIRChannel.postMessage(formattedOutput.trim());
                return;
              }
              
              // Fallback: if we can't extract structured sections, get the entire grid text
              console.log("Using grid container text as fallback");
              EOIRChannel.postMessage(gridContainer.innerText.trim());
              return;
            }
            
            // Final fallback: get text from main or body
            console.log("Using page content as fallback");
            const pageContent = document.querySelector("main") || document.body;
            EOIRChannel.postMessage(pageContent.innerText.trim());
            
          } catch (e) {
            console.error("Error extracting case info: " + e);
            EOIRChannel.postMessage('Toque para ver estado');
          }
        }
        
        // Function to handle when a case is not found (error message)
        function handleCaseNotFound() {
          console.log("Checking for error message");
          try {
            // Check for specific error message with exact class
            const errorMsg = document.querySelector('.font-bold.my-1.text-red.text-lg.italic.text-left');
            if (errorMsg) {
              console.log("Found error message: " + errorMsg.textContent);
              EOIRChannel.postMessage(errorMsg.textContent.trim());
              return;
            }
            
            // Fallback to any error with text-red class
            const anyErrorMsg = document.querySelector('.text-red');
            if (anyErrorMsg && anyErrorMsg.textContent.includes('No hay información')) {
              console.log("Found generic error message");
              EOIRChannel.postMessage(anyErrorMsg.textContent.trim());
              return;
            }
            
            console.log("No recognizable state found");
            EOIRChannel.postMessage('Toque para ver estado');
          } catch (e) {
            console.error("Error handling case not found: " + e);
            EOIRChannel.postMessage('Toque para ver estado');
          }
        }
        
        // More aggressive URL monitoring
        let lastUrl = window.location.href;
        const urlChecker = setInterval(function() {
          const currentUrl = window.location.href;
          if (currentUrl !== lastUrl) {
            console.log("URL changed from " + lastUrl + " to " + currentUrl);
            lastUrl = currentUrl;
            
            if (currentUrl.includes('caseInformation')) {
              console.log("Detected navigation to case info page, waiting for content to load");
              setTimeout(function() {
                console.log("Processing case info page");
                handleCaseFound();
                clearInterval(urlChecker);
              }, 2000);
            }
          }
        }, 300);
        
        // Process error messages as they appear
        const observer = new MutationObserver(function(mutations) {
          if (!window.location.href.includes('caseInformation')) {
            const errorMsg = document.querySelector('.font-bold.my-1.text-red.text-lg.italic.text-left');
            if (errorMsg) {
              console.log("Mutation observer found error message");
              handleCaseNotFound();
              observer.disconnect();
              clearInterval(urlChecker);
            }
          }
        });
        
        observer.observe(document.body, { 
          childList: true, 
          subtree: true,
          characterData: true
        });
        
        // Set shorter timeout
        setTimeout(function() {
          if (window.location.href.includes('caseInformation')) {
            console.log("Timeout reached on case info page");
            handleCaseFound();
          } else {
            console.log("Timeout reached on main page");
            handleCaseNotFound();
          }
          observer.disconnect();
          clearInterval(urlChecker);
        }, 15000);
        
        // Try to click the Accept button
        const acceptButton = document.querySelector('button.btn');
        if (acceptButton && acceptButton.innerText.includes('Acepto')) {
          console.log("Found accept button, clicking it");
          acceptButton.click();
          setTimeout(function() {
            fillAlienNumber();
          }, 1000);
        } else {
          // Check if form is already visible
          const inputFields = document.querySelectorAll('.codeInput input[type="number"]');
          if (inputFields && inputFields.length === 9) {
            fillAlienNumber();
          }
        }
        
        // Function to fill in the alien number
        function fillAlienNumber() {
          // Get all 9 input fields
          const inputFields = document.querySelectorAll('.codeInput input[type="number"]');
          if (!inputFields || inputFields.length !== 9) {
            console.log("Input fields not found or count incorrect");
            return;
          }
          
          console.log("Found " + inputFields.length + " input fields");
          
          // Extract the digits from the alien number
          const digits = '${_alienNumberDigits}'.padStart(9, '0').slice(-9).split('');
          console.log("Will input: " + digits.join(''));
          
          // Fill each input field one by one with a slight delay
          for (let i = 0; i < inputFields.length; i++) {
            setTimeout(() => {
              const input = inputFields[i];
              
              // Clear the field first
              input.value = '';
              
              // Use React's property descriptor to set the value
              const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
              nativeInputValueSetter.call(input, digits[i]);
              
              // Trigger multiple events to ensure React detects the change
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              input.dispatchEvent(new KeyboardEvent('keydown', { key: digits[i], bubbles: true }));
              input.dispatchEvent(new KeyboardEvent('keyup', { key: digits[i], bubbles: true }));
              
              console.log("Set digit " + (i+1) + " to " + digits[i]);
              
              // If this is the last digit, set up the button click
              if (i === inputFields.length - 1) {
                setTimeout(() => {
                  const submitButton = document.getElementById('btn_submit');
                  if (submitButton) {
                    console.log("Found submit button, clicking");
                    submitButton.disabled = false;
                    submitButton.removeAttribute('disabled');
                    submitButton.click();
                    
                    // Monitor for URL change or error after submission
                    console.log("Waiting for response after submit");
                  } else {
                    console.log("Submit button not found");
                  }
                }, 500);
              }
            }, i * 200); // 200ms between each digit
          }
        }
      })();
    ''');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showUI) return const SizedBox.shrink(); // Headless WebView

    return WillPopScope(
      onWillPop: () async => true, // Allow user to go back
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estado de Caso EOIR'),
          automaticallyImplyLeading: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () {
                Navigator.pop(context, 'Toque para ver estado');
              },
              tooltip: 'Terminar',
            ),
          ],
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