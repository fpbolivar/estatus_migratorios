import 'package:flutter/material.dart';
import 'case_list_page.dart';
import 'case_service.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final CaseService caseService = CaseService(); // simple constructor

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Estatus Migratorios USCIS y EOIR',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CaseListPage(service: caseService),
    );
  }
}
