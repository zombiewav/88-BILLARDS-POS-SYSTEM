import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/tables.dart' show newId;

/// A product photo, or a placeholder icon when there is none (or it went missing).
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.path, this.size, this.radius = 12});

  final String? path;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.local_drink_outlined,
          size: size == null ? 40 : size! * 0.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final image = path == null
        ? placeholder
        : Image.file(
            File(path!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          );

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: image),
    );
  }
}

/// Copies a picked photo into the app's own folder so it survives the original
/// being moved or deleted. Returns the new path.
Future<String> storeProductImage(String sourcePath) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'product_images'));
  await dir.create(recursive: true);
  final target = p.join(dir.path, '${newId()}${p.extension(sourcePath)}');
  await File(sourcePath).copy(target);
  return target;
}
