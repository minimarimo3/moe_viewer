/*
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


import 'dart:io';
import 'package:flutter/material.dart';

class DetailScreen extends StatefulWidget {
  final List<File> imageFileList; // 全画像のリスト
  final int initialIndex;         // 最初に表示する画像のインデックス

  const DetailScreen({
    super.key,
    required this.imageFileList,
    required this.initialIndex,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late PageController _pageController; // PageViewをコントロールするためのもの

  @override
  void initState() {
    super.initState();
    // 最初に表示するページを指定してPageControllerを作成
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageFileList.length,
        itemBuilder: (context, index) {
          // 各ページに画像を表示
          return InteractiveViewer( // ピンチズーム機能はそのまま
            child: Center(
              child: Image.file(widget.imageFileList[index]),
            ),
          );
        },
      ),
    );
  }
}
*/

// lib/detail_screen.dart

import 'dart:async'; // ★★★ Timerを使うためにインポート
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ★★★ SystemChromeを使うためにインポート

class DetailScreen extends StatefulWidget {
  final List<File> imageFileList;
  final int initialIndex;

  const DetailScreen({
    super.key,
    required this.imageFileList,
    required this.initialIndex,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late PageController _pageController;
  bool _isUiVisible = true; // ★★★ UIの表示状態を管理する変数

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);

    // ★★★ 画面を開いて0秒後に自動でUIを隠す
    Timer(const Duration(seconds: 0), () {
      if (mounted) {
        _toggleUiVisibility();
      }
    });
  }

  @override
  void dispose() {
    // ★★★ この画面を離れるときに、必ずシステムUIを元に戻す
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ★★★ UIの表示/非表示を切り替える関数 ★★★
  void _toggleUiVisibility() {
    setState(() {
      _isUiVisible = !_isUiVisible;

      if (_isUiVisible) {
        // UIを表示する（システムUIも元に戻す）
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        // UIを隠す（システムUIも全て隠す）
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ★★★ _isUiVisibleの値に応じてAppBarを表示/非表示
      appBar: _isUiVisible
          ? AppBar(backgroundColor: Colors.black.withOpacity(0.3))
          : null,
      // AppBarの高さを考慮するために必要
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      // ★★★ 画面全体をGestureDetectorで囲んでタップを検知
      body: GestureDetector(
        onTap: _toggleUiVisibility,
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.imageFileList.length,
          itemBuilder: (context, index) {
            return InteractiveViewer(
              child: Center(child: Image.file(widget.imageFileList[index])),
            );
          },
        ),
      ),
    );
  }
}
