import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' show parse;
// Note: CookieManager might not be needed if the headless webview handles sessions automatically,
// but we'll keep the structure in case it's needed for sharing with the visible webview.
import 'cookie_manager.dart';

class CaseService {
  final String _baseUrl = 'https://egov.uscis.gov/casestatus/mycasestatus.do';
  final List<String> _cases = [];

  // fetch all cases
  Future<List<String>> getCases() async {
    return _cases;
  }

  // fetch status for a specific case
  Future<String> fetchCaseStatus(String caseNumber) async {
    final Completer<String> completer = Completer();
    HeadlessInAppWebView? headlessWebView;

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_baseUrl)),
      onLoadStop: (controller, url) async {
        try {
          // Check if we are on the results page by looking for the status elements
          final html = await controller.getHtml();
          if (html != null) {
            final document = parse(html);
            final statusElement = document.querySelector('.rows h1');
            final detailsElement = document.querySelector('.rows p');

            if (statusElement != null && detailsElement != null) {
              final status = '${statusElement.text.trim()}\n${detailsElement.text.trim()}';
              if (!completer.isCompleted) {
                completer.complete(status);
              }
              return; // Stop further processing
            }
          }

          // If no status found, check if we are on the initial form page to submit
          final pageTitle = await controller.getTitle();
          if (pageTitle?.contains("Case Status Online") ?? false) {
            await controller.evaluateJavascript(source: """
              document.getElementById('receipt_number').value = '$caseNumber';
              document.querySelector('input[name="checkStatus"]').click();
            """);
          } else if (html != null && html.contains("Verifique el Estatus de su Caso")) {
             // This means we hit a CAPTCHA
            if (!completer.isCompleted) {
              completer.complete("Toque para ver estado");
            }
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.complete("Error: ${e.toString()}");
          }
        }
      },
      onLoadError: (controller, url, code, message) {
        if (!completer.isCompleted) {
          completer.complete("Error: Failed to load page - $message");
        }
      },
    );

    try {
      // Run the webview in the background. Do NOT await this.
      headlessWebView.run();

      // Await the result from the completer, with a timeout.
      final result = await completer.future.timeout(const Duration(seconds: 30),
          onTimeout: () {
        return "Error: Request timed out.";
      });
      
      return result;
    } catch (e) {
      return "Error: ${e.toString()}";
    } finally {
      // This is crucial: always dispose of the webview to free resources.
      await headlessWebView?.dispose();
    }
  }

  // add a new case
  Future<void> addCase(String caseNumber) async {
    if (!_cases.contains(caseNumber)) _cases.add(caseNumber);
  }

  // delete a case
  Future<void> deleteCase(String caseNumber) async {
    _cases.remove(caseNumber);
  }
}
