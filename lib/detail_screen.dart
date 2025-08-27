import 'dart:io';
import 'package:flutter/material.dart';
import 'package:exif/exif.dart'; // ★★★ exif パッケージをインポート ★★★

class DetailScreen extends StatefulWidget {
  final File imageFile;

  const DetailScreen({super.key, required this.imageFile});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, String> _exifData = {};

  @override
  void initState() {
    super.initState();
    _loadExifData();
  }

  // exifパッケージを使った、シンプルで確実な方法
  Future<void> _loadExifData() async {
    final bytes = await widget.imageFile.readAsBytes();
    // readExifFromBytes は Map<String, IfdTag> を返す
    final data = await readExifFromBytes(bytes);

    if (data.isEmpty) {
      print("No Exif found");
      return;
    }

    Map<String, String> extractedData = {};
    // 欲しい情報をキーで直接取得！
    final dateTime = data['Image DateTime'];
    final make = data['Image Make'];
    final model = data['Image Model'];

    if (dateTime != null) {
      extractedData['DateTime'] = dateTime.printable;
    }
    if (make != null) {
      extractedData['Make'] = make.printable;
    }
    if (model != null) {
      extractedData['Model'] = model.printable;
    }

    if (mounted) {
      setState(() {
        _exifData = extractedData;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: InteractiveViewer(child: Image.file(widget.imageFile))),
          if (_exifData.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16.0),
                color: Colors.black.withOpacity(0.6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _exifData.entries.map((entry) {
                    return Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
