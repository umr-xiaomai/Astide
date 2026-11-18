import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Full-screen pinch-zoomable viewer for chat and Moments images (raster or SVG).
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.imagePath,
    this.title = '',
  });

  final String imagePath;
  final String title;

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    final isSvg = imagePath.toLowerCase().endsWith('.svg');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: title.isNotEmpty
            ? Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              )
            : null,
      ),
      body: Center(
        child: file.existsSync()
            ? InteractiveViewer(
                minScale: 0.8,
                maxScale: 5.0,
                child: isSvg
                    ? SvgPicture.file(file, width: 340, height: 260, fit: BoxFit.contain)
                    : Image.file(file, fit: BoxFit.contain),
              )
            : const Text(
                '图片文件不存在或已被移除',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
      ),
    );
  }
}
