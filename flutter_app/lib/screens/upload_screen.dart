// lib/screens/upload_screen.dart  (V5 — professional icon-based UI)
// Four input modes: PDF/DOCX, YouTube URL, Webpage URL, Camera OCR.
// All modes feed into the same POST /process pipeline after ingestion.

import 'dart:io';
import 'dart:math' as math;
import 'package:confetti/confetti.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../main.dart' show slideRoute;
import 'results_screen.dart';

class UploadScreen extends StatefulWidget {
  final bool isFirstUpload;
  const UploadScreen({super.key, this.isFirstUpload = false});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

// Add after _TypePill class:

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String   label, sub;
  final Color    color;
  final VoidCallback onTap;
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.20)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(child: Icon(icon, color: color, size: 20)),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(fontSize: 11, color: AppColors.textSecond)),
          ]),
          const Spacer(),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 13, color: AppColors.textSecond),
        ]),
      ),
    );
  }
}

class _UploadScreenState extends State<UploadScreen>
    with TickerProviderStateMixin {
  final _api  = ApiService();

  int _mode = 0;

  File?   _file;
  String? _fileName;
  double  _fileSizeMb = 0;

  final _urlCtrl = TextEditingController();

  bool    _uploading  = false;
  bool    _processing = false;
  String  _statusMsg  = '';
  String? _error;
  int     _step       = 0;

  bool    _isDragOver = false;

  late ConfettiController _confetti;
  bool _isOffline = false;

  bool get _busy => _uploading || _processing;

  static const _steps = [
    (icon: Icons.upload_rounded,       label: 'Upload'),
    (icon: Icons.text_snippet_rounded, label: 'Extract'),
    (icon: Icons.auto_awesome_rounded, label: 'Generate'),
    (icon: Icons.check_circle_rounded, label: 'Done'),
  ];

  static const _modes = [
    (icon: Icons.upload_file_rounded,  label: 'File'),
    (icon: Icons.play_circle_rounded,  label: 'YouTube'),
    (icon: Icons.language_rounded,     label: 'URL'),
    (icon: Icons.camera_alt_rounded,   label: 'Scan'),
  ];

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
    Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _isOffline) setState(() => _isOffline = offline);
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  bool _validateFile(String path, String name, int sizeBytes) {
    final f      = File(path);
    final actual = f.existsSync() ? f.lengthSync() : sizeBytes;
    final sizeMb = actual / (1024 * 1024);
    if (sizeMb > 50) {
      setState(() => _error = 'File is ${sizeMb.toStringAsFixed(1)} MB — max 50 MB.');
      return false;
    }
    final ext = name.split('.').last.toLowerCase();
    if (!['pdf', 'doc', 'docx'].contains(ext)) {
      setState(() => _error = 'Only PDF or DOCX files are supported.');
      return false;
    }
    setState(() {
      _file = File(path);
      _fileName = name;
      _fileSizeMb = sizeMb;
      _error = null;
    });
    return true;
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    _validateFile(picked.path!, picked.name, picked.size);
  }

  Future<void> _pickImage() async {
    // Let user choose camera or gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Select Image Source',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              _SourceTile(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                sub: 'Use your camera',
                color: AppColors.primary,
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 10),
              _SourceTile(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                sub: 'Pick an existing image',
                color: AppColors.accentGreen,
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2400,   // cap resolution — reduces size without killing OCR quality
      maxHeight: 2400,
    );
    if (picked == null) return;

    final f       = File(picked.path);
    final sizeMb  = await f.length() / (1024 * 1024);
    if (sizeMb > 10) {
      if (mounted) setState(() => _error = 'Image is ${sizeMb.toStringAsFixed(1)} MB — max 10 MB. Try a lower resolution.');
      return;
    }

    if (mounted) {
      setState(() {
        _file      = f;
        _fileName  = picked.name;
        _error     = null;
      });
    }
  }

  Future<void> _run() async {
    HapticFeedback.lightImpact();
    final uid = AuthService.userId;
    if (uid.isEmpty) {
      setState(() => _error = 'You must be signed in.');
      return;
    }

    // Validate URL modes before hitting the server
    if (_mode == 1 || _mode == 2) {
      final url = _urlCtrl.text.trim();
      if (!_isValidUrl(url)) {
        setState(() => _error =
        'Please enter a valid URL starting with https://');
        return;
      }
    }

    setState(() {
      _uploading = true;
      _step = 1;
      _error = null;
      _statusMsg = 'Uploading…';
    });

    try {
      Map<String, dynamic> ingestData;

      switch (_mode) {
        case 0:
          ingestData = await _api.uploadFile(file: _file!, userId: uid);
        case 1:
          setState(() => _statusMsg = 'Fetching YouTube transcript…');
          ingestData = await _api.ingestYouTube(url: _urlCtrl.text.trim(), userId: uid);
        case 2:
          setState(() => _statusMsg = 'Scraping webpage…');
          ingestData = await _api.ingestUrl(url: _urlCtrl.text.trim(), userId: uid);
        case 3:
          setState(() => _statusMsg = 'Running OCR on image…');
          ingestData = await _api.ingestOcr(imageFile: _file!, userId: uid);
        default:
          throw 'Unknown mode.';
      }

      if (!mounted) return;
      final resultId      = ingestData['result_id'] as String;
      final extractedText = ingestData['extracted_text'] as String;

      setState(() { _step = 2; _statusMsg = 'Extracting text…'; });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      setState(() {
        _uploading = false;
        _processing = true;
        _step = 3;
        _statusMsg = 'AI is generating your study materials… (30–60 s)';
      });

      final studyResult = await _api.processDocument(
        resultId: resultId,
        extractedText: extractedText,
        userId: uid,
      ).timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw 'Request timed out. The AI is taking too long — please retry.',
      );

      if (!mounted) return;
      setState(() { _step = 4; });

      if (widget.isFirstUpload) {
        _confetti.play();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          slideRoute(ResultsScreen(resultId: studyResult.resultId)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _uploading = false;
        _processing = false;
        _step = 0;
        _statusMsg = '';
        if (_mode == 1 || _mode == 2) _urlCtrl.clear();
      });
    }
  }

  bool get _canRun {
    if (_busy || _isOffline) return false;
    if (_mode == 0 || _mode == 3) return _file != null;
    return _isValidUrl(_urlCtrl.text.trim());
  }

  bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF0EDE8),
          body: SafeArea(
            child: Column(
              children: [
                _buildOfflineBanner(),
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        _buildModePicker(),
                        const SizedBox(height: 14),
                        _buildInputArea(),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _buildErrorCard(),
                        ],
                        if (_busy || _step == 4) ...[
                          const SizedBox(height: 14),
                          _buildStepProgress(),
                        ],
                        const SizedBox(height: 14),
                        _buildCTA(),
                        const SizedBox(height: 14),
                        _buildTipsCard(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirection: math.pi / 2,
            emissionFrequency: 0.05,
            numberOfParticles: 20,
            maxBlastForce: 20,
            minBlastForce: 8,
            gravity: 0.2,
            colors: const [
              Color(0xFF6C63FF), Color(0xFF4FC3F7),
              Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFF06292),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      height: _isOffline ? 40 : 0,
      color: AppColors.accentRed.withOpacity(0.90),
      child: _isOffline
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 15),
        const SizedBox(width: 8),
        const Text(
          "You're offline — uploads unavailable",
          style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500),
        ),
      ])
          : null,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: AppColors.textSecond),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CREATE',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecond,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.4)),
                const SizedBox(height: 1),
                Text('New Session',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_modes[_mode].icon, size: 12, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(_modes[_mode].label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ]),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.06);
  }

  Widget _buildModePicker() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(_modes.length, (i) {
          final selected = i == _mode;
          return Expanded(
            child: GestureDetector(
              onTap: _busy
                  ? null
                  : () {
                HapticFeedback.selectionClick();
                setState(() {
                  _mode = i;
                  _file = null;
                  _fileName = null;
                  _urlCtrl.clear();
                  _error = null;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: selected ? AppColors.ctaBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(children: [
                  Icon(_modes[i].icon,
                      size: 20,
                      color: selected ? Colors.white : AppColors.textSecond),
                  const SizedBox(height: 4),
                  Text(_modes[i].label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppColors.textSecond)),
                ]),
              ),
            ),
          );
        }),
      ),
    ).animate().fadeIn(delay: 80.ms, duration: 400.ms);
  }

  Widget _buildInputArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim,
              child: SlideTransition(
                  position: Tween(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero).animate(anim),
                  child: child)),
      child: KeyedSubtree(
        key: ValueKey(_mode),
        child: switch (_mode) {
          0 => _buildFilePicker(),
          1 => _buildUrlField('YouTube URL',
              'https://youtube.com/watch?v=XXXXXXXXXXX  or  https://youtu.be/XXXXX',Icons.play_circle_rounded),
          2 => _buildUrlField('Webpage URL',
              'https://en.wikipedia.org/wiki/...', Icons.language_rounded),
          3 => _buildOcrPicker(),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _buildFilePicker() {
    final hasFile = _file != null;
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        setState(() => _isDragOver = true);
        return true;
      },
      onLeave: (_) => setState(() => _isDragOver = false),
      onAcceptWithDetails: (d) {
        setState(() => _isDragOver = false);
        final f = File(d.data);
        _validateFile(
            d.data, d.data.split(Platform.pathSeparator).last, f.lengthSync());
      },
      builder: (_, __, ___) => GestureDetector(
        onTap: _busy ? null : _pickFile,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _isDragOver
                ? AppColors.accentAmber.withOpacity(0.06)
                : hasFile
                ? AppColors.primaryGlow
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: _isDragOver
                    ? AppColors.accentAmber
                    : hasFile
                    ? AppColors.primary.withOpacity(0.4)
                    : AppColors.border,
                width: hasFile ? 1.5 : 1),
          ),
          child: hasFile
              ? Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.insert_drive_file_outlined,
                    size: 22, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fileName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text('${_fileSizeMb.toStringAsFixed(1)} MB · Ready to process',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecond)),
                ],
              ),
            ),
            if (!_busy)
              GestureDetector(
                onTap: () => setState(() {
                  _file = null;
                  _fileName = null;
                }),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: AppColors.textSecond),
                ),
              ),
          ])
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: _isDragOver
                      ? AppColors.accentAmber.withOpacity(0.12)
                      : AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    _isDragOver
                        ? Icons.file_download_rounded
                        : Icons.upload_file_rounded,
                    size: 26,
                    color: _isDragOver
                        ? AppColors.accentAmber
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _isDragOver ? 'Drop it here!' : 'Tap to select a file',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
            Text('PDF or DOCX · Max 50 MB',
            style: TextStyle(
                      fontSize: 12, color: AppColors.textSecond)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _TypePill(label: 'PDF',  icon: Icons.picture_as_pdf_outlined),
                  const SizedBox(width: 8),
                  _TypePill(label: 'DOC',  icon: Icons.description_outlined),
                  const SizedBox(width: 8),
                  _TypePill(label: 'DOCX', icon: Icons.description_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlField(String label, String placeholder, IconData prefixIcon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecond,
                  letterSpacing: 0.5)),
          const SizedBox(height: 10),
          TextField(
            controller: _urlCtrl,
            enabled: !_busy,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: TextStyle(color: AppColors.textSecond.withOpacity(0.5), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFFF0EDE8),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(prefixIcon, color: AppColors.primary, size: 18),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 44),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_urlCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final valid = _isValidUrl(_urlCtrl.text.trim());
              return Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: valid
                        ? AppColors.primaryGlow
                        : AppColors.accentRed.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: valid
                          ? AppColors.primary.withOpacity(0.20)
                          : AppColors.accentRed.withOpacity(0.30),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      valid
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 11,
                      color: valid ? AppColors.primary : AppColors.accentRed,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      valid
                          ? 'URL entered'
                          : (_mode == 1
                          ? 'Paste the full YouTube link'
                          : 'Must start with https://'),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: valid
                              ? AppColors.primary
                              : AppColors.accentRed),
                    ),
                  ]),
                ),
              ]);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildOcrPicker() {
    final hasImage = _file != null;
    return GestureDetector(
      onTap: _busy ? null : _pickImage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: hasImage
              ? AppColors.accentGreen.withOpacity(0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: hasImage
                  ? AppColors.accentGreen.withOpacity(0.5)
                  : AppColors.border,
              width: hasImage ? 1.5 : 1),
        ),
        child: hasImage
            ? Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(_file!,
                width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Image selected',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text('Tap to change photo',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecond)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded,
                        size: 11,
                        color: AppColors.accentGreen),
                    const SizedBox(width: 4),
                    Text('Ready for OCR',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentGreen)),
                  ]),
                ),
              ],
            ),
          ),
        ])
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Icon(Icons.camera_alt_rounded,
                    size: 26, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 14),
            Text('Take a photo of your notes',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('JPEG or PNG · Camera or Gallery',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecond)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded,
            color: AppColors.accentRed, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_error!,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.accentRed)),
        ),
      ]),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.05);
  }

  Widget _buildStepProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (_statusMsg.isNotEmpty) ...[
            Row(children: [
              if (_step < 4)
                SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _step == 3
                            ? AppColors.accentAmber
                            : AppColors.primary))
              else
                Icon(Icons.check_circle_rounded,
                    color: AppColors.accentGreen, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_statusMsg,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textBody,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          Row(
            children: List.generate(_steps.length, (i) {
              final stepNum  = i + 1;
              final isDone   = _step > stepNum;
              final isActive = _step == stepNum;
              final color = isDone
                  ? AppColors.accentGreen
                  : isActive
                  ? AppColors.primary
                  : AppColors.border;
              final bg = isDone
                  ? AppColors.accentGreen.withOpacity(0.10)
                  : isActive
                  ? AppColors.primaryGlow
                  : const Color(0xFFF0EDE8);
              return Expanded(
                child: Row(children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: color.withOpacity(isActive ? 0.4 : 0.25)),
                      ),
                      child: Column(children: [
                        Icon(
                          isDone ? Icons.check_rounded : _steps[i].icon,
                          size: 15,
                          color: isDone
                              ? AppColors.accentGreen
                              : isActive
                              ? AppColors.primary
                              : AppColors.textSecond.withOpacity(0.4),
                        ),
                        const SizedBox(height: 4),
                        Text(_steps[i].label,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDone
                                    ? AppColors.accentGreen
                                    : isActive
                                    ? AppColors.primary
                                    : AppColors.textSecond.withOpacity(0.4))),
                      ]),
                    ),
                  ),
                  if (i < _steps.length - 1)
                    AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: 6, height: 2,
                        color: _step > stepNum
                            ? AppColors.accentGreen
                            : AppColors.border.withOpacity(0.5)),
                ]),
              );
            }),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06);
  }

  Widget _buildCTA() {
    final label = _isOffline
        ? 'No internet connection'
        : (_mode == 0 || _mode == 3) && _file == null
        ? 'Select a source first'
        : (_mode == 1 || _mode == 2) && _urlCtrl.text.trim().isEmpty
        ? 'Paste a URL first'
        : _busy
        ? 'Processing…'
        : 'Generate Study Materials';

    return GestureDetector(
      onTap: _canRun ? _run : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: _canRun ? AppColors.ctaBlue : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: _canRun
              ? null
              : Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            _isOffline
                ? Icons.wifi_off_rounded
                : _busy
                ? Icons.hourglass_top_rounded
                : Icons.bolt_rounded,
            color: _canRun ? Colors.white : AppColors.textSecond,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _canRun ? Colors.white : AppColors.textSecond)),
        ]),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 350.ms);
  }

  // ── Tips card — emojis replaced with contextual icon badges ───────────────

  Widget _buildTipsCard() {
    final tips = [
      if (_mode == 0)
        (icon: Icons.picture_as_pdf_outlined,
        color: AppColors.accentRed,
        text: 'Text-based PDFs work best — not scanned images'),
      if (_mode == 1)
        (icon: Icons.closed_caption_outlined,
        color: AppColors.accentRed,
        text: 'Video must have captions (auto-generated is fine)'),
      if (_mode == 2)
        (icon: Icons.article_outlined,
        color: AppColors.primary,
        text: 'Wikipedia articles and blog posts work great'),
      if (_mode == 3)
        (icon: Icons.wb_sunny_outlined,
        color: AppColors.accentAmber,
        text: 'Use good lighting and hold the camera steady'),
      (icon: Icons.compress_rounded,
      color: AppColors.primary,
      text: 'Only the first ~3 000 characters are processed'),
      (icon: Icons.schedule_rounded,
      color: AppColors.textSecond,
      text: 'AI generation takes 30–90 seconds on first run'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tips',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${tips.length}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(tips.length, (i) {
            final t      = tips[i];
            final isLast = i == tips.length - 1;
            return Container(
              padding: EdgeInsets.only(
                  top: i == 0 ? 0 : 10,
                  bottom: isLast ? 0 : 10),
              decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                      bottom: BorderSide(
                          color: AppColors.border.withOpacity(0.5)))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: t.color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(t.icon, size: 14, color: t.color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(t.text,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: AppColors.textBody)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 350.ms);
  }
}

// ─── Type pill chip ────────────────────────────────────────────────────────────

class _TypePill extends StatelessWidget {
  final String   label;
  final IconData icon;
  const _TypePill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryGlow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
      ]),
    );
  }
}