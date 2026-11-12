import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_identity.dart';

export '../domain/app_identity.dart';

final appVersionProvider = Provider<String>((ref) => unknownAppVersion);
