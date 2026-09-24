import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// A photo that is either already uploaded (https URL) or still a local file
/// picked a moment ago. Lets previews show unsaved photos.
ImageProvider imageFor(String src) => src.startsWith('http') ? CachedNetworkImageProvider(src) : FileImage(File(src));
