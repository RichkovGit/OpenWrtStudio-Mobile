import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:luci_mobile/services/ota_service.dart';

class OtaUpdateDialog extends StatefulWidget {
  final OtaReleaseInfo releaseInfo;
  final String currentVersion;

  const OtaUpdateDialog({
    super.key,
    required this.releaseInfo,
    required this.currentVersion,
  });

  static Future<void> show(
    BuildContext context, {
    required OtaReleaseInfo releaseInfo,
    required String currentVersion,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OtaUpdateDialog(
        releaseInfo: releaseInfo,
        currentVersion: currentVersion,
      ),
    );
  }

  @override
  State<OtaUpdateDialog> createState() => _OtaUpdateDialogState();
}

class _OtaUpdateDialogState extends State<OtaUpdateDialog> {
  final OtaService _otaService = OtaService();
  CancelToken? _cancelToken;
  bool _isDownloading = false;
  double _progress = 0.0;
  String _progressStatus = '';
  String? _errorMessage;

  void _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _errorMessage = null;
      _progressStatus = 'Подготовка к загрузке...';
      _cancelToken = CancelToken();
    });

    final success = await _otaService.downloadAndInstall(
      downloadUrl: widget.releaseInfo.apkUrl,
      version: widget.releaseInfo.version,
      cancelToken: _cancelToken,
      onProgress: (progress, received, total) {
        if (!mounted) return;
        final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
        final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
        setState(() {
          _progress = progress;
          _progressStatus = '$recMb MB / $totMb MB (${(progress * 100).toInt()}%)';
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      if (!success && _cancelToken?.isCancelled != true) {
        _errorMessage = 'Не удалось загрузить или запустить установку. Попробуйте скачать вручную.';
      }
    });

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    setState(() {
      _isDownloading = false;
      _progressStatus = 'Загрузка отменена';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E242B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00D2FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.system_update, color: Color(0xFF00D2FF), size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Доступно обновление!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  'v${widget.currentVersion}  ➔  v${widget.releaseInfo.version}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF00D2FF), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            if (widget.releaseInfo.formattedSize.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Размер APK: ${widget.releaseInfo.formattedSize}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            if (!_isDownloading && _errorMessage == null) ...[
              const Text('Что нового:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF13181D) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.releaseInfo.body.isNotEmpty
                        ? widget.releaseInfo.body
                        : 'Улучшена стабильность работы, оптимизировано управление клиентами и инструментами LuCI.',
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00D2FF)),
                borderRadius: BorderRadius.circular(4),
                minHeight: 8,
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _progressStatus,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_isDownloading)
          TextButton(
            onPressed: _cancelDownload,
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Позже', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => launchUrlString(
              'https://github.com/${OtaService.repo}/releases/tag/${widget.releaseInfo.tagName}',
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('GitHub', style: TextStyle(color: Color(0xFF00D2FF))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Обновить (OTA)', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _startDownload,
          ),
        ],
      ],
    );
  }
}
