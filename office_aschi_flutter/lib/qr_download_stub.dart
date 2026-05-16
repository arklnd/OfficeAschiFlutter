import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

void saveBytes(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
}
