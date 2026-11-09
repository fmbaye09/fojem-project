import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_text_styles.dart';

/// « FOJËM Pro v1.6.0 » : la version réellement installée (pubspec), pour
/// que le support sache tout de suite de quelle version parle le chauffeur.
class AppVersionLabel extends StatelessWidget {
  final String appName;

  const AppVersionLabel({super.key, required this.appName});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        return Text(
          version == null || version.isEmpty ? appName : '$appName v$version',
          style: AppTextStyles.caption,
        );
      },
    );
  }
}
