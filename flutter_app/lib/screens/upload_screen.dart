// lib/screens/upload_screen.dart  (V3)
// Four input modes: PDF/DOCX, YouTube URL, Webpage URL, Camera OCR.
// All modes feed into the same POST /process pipeline after ingestion.

import 'dart:io';
import 'dart:math' as math;
import 'package:confetti/confetti.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

class _UploadScreenState extends State<UploadScreen>
    with TickerProviderStateMixin {
  final _api  = ApiService();
  final _auth = AuthService();

  // Selected input mode: 0=file, 1=youtube, 2=url, 3=ocr
  int _mode = 0;

  // File mode
  File?   _file;
  String? _fileName;
  double  _fileSizeMb = 0;

  // URL / YouTube mode
  final _urlCtrl = TextEditingController();

  // State
  bool    _uploading  = false;
  bool    _processing = false;
  String  _statusMsg  = '';
  String? _error;
  int     _step       = 0;   // 0=idle 1=upload 2=extract 3=generate 4=done

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
    (icon: Icons.upload_file_rounded,   label: 'File'),
    (icon: Icons.play_circle_rounded,   label: 'YouTube'),
    (icon: Icons.language_rounded,      label: 'URL'),
    (icon: Icons.camera_alt_rounded,    label: 'Scan'),
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

  // ── Validation ────────────────────────────────────────────────────────────

  bool _validateFile(String path, String name, int sizeBytes) {
    final sizeMb = sizeBytes / (1024 * 1024);
    if (sizeMb > 10) {
      setState(() => _error = 'File is ${sizeMb.toStringAsFixed(1)} MB — max 10 MB.');
      return false;
    }
    final ext = name.split('.').last.toLowerCase();
    if (!['pdf', 'doc', 'docx'].contains(ext)) {
      setState(() => _error = 'Only PDF or DOCX files are supported.');
      return false;
    }
    setState(() { _file = File(path); _fileName = name; _fileSizeMb = sizeMb; _error = null; });
    return true;
  }

  // ── Pick file ─────────────────────────────────────────────────────────────

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

  // ── Pick image for OCR ────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;
    final f = File(picked.path);
    setState(() { _file = f; _fileName = picked.name; _error = null; });
  }

  // ── Run ingestion ─────────────────────────────────────────────────────────

  Future<void> _run() async {
    String? uid = _auth.userId;
    if (uid == null) {
      try { await Supabase.instance.client.auth.refreshSession(); uid = _auth.userId; }
      catch (_) {}
    }
    if (uid == null) { setState(() => _error = 'You must be signed in.'); return; }

    setState(() { _uploading = true; _step = 1; _error = null; _statusMsg = 'Uploading…'; });

    try {
      Map<String, dynamic> ingestData;

      switch (_mode) {
        case 0: // File
          ingestData = await _api.uploadFile(file: _file!, userId: uid);
        case 1: // YouTube
          setState(() => _statusMsg = 'Fetching YouTube transcript…');
          ingestData = await _api.ingestYouTube(url: _urlCtrl.text.trim(), userId: uid);
        case 2: // URL
          setState(() => _statusMsg = 'Scraping webpage…');
          ingestData = await _api.ingestUrl(url: _urlCtrl.text.trim(), userId: uid);
        case 3: // OCR
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

      setState(() { _uploading = false; _processing = true; _step = 3;
        _statusMsg = 'AI is generating your study materials… (30–60 s)'; });

      final studyResult = await _api.processDocument(
        resultId: resultId, extractedText: extractedText, userId: uid,
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
      setState(() { _error = e.toString(); _uploading = false; _processing = false; _step = 0; _statusMsg = ''; });
    }
  }

  bool get _canRun {
    if (_busy || _isOffline) return false;
    if (_mode == 0 || _mode == 3) return _file != null;
    return _urlCtrl.text.trim().isNotEmpty;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            leading: BackButton(color: AppColors.textSecond),
            title: Text('New Session', style: AppText.subheading),
          ),
          body: Container(
            decoration: const BoxDecoration(gradient: AppColors.bgGrad),
            child: Column(
              children: [
                _buildOfflineBanner(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildModePicker(),
                        const SizedBox(height: 16),

                        // Mode-specific input
                        if (_mode == 0) _buildFilePicker(),
                        if (_mode == 1) _buildUrlField('Paste YouTube URL', 'https://youtube.com/watch?v=...'),
                        if (_mode == 2) _buildUrlField('Paste webpage URL', 'https://en.wikipedia.org/wiki/...'),
                        if (_mode == 3) _buildOcrPicker(),

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _buildErrorCard(),
                        ],

                        if (_busy || _step == 4) ...[
                          const SizedBox(height: 16),
                          _buildStepProgress(),
                        ],

                        const SizedBox(height: 20),
                        _buildCTA(),
                        const SizedBox(height: 20),
                        _buildTips(),
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
            colors: const [Color(0xFF6C63FF), Color(0xFF4FC3F7),
                Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFF06292)],
          ),
        ),
      ],
    );
  }

  // ── Mode picker ───────────────────────────────────────────────────────────

  Widget _buildModePicker() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(_modes.length, (i) {
          final selected = i == _mode;
          return Expanded(
            child: GestureDetector(
              onTap: _busy ? null : () => setState(() {
                _mode = i; _file = null; _fileName = null;
                _urlCtrl.clear(); _error = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.primaryGrad : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Icon(_modes[i].icon,
                      size: 20,
                      color: selected ? Colors.white : AppColors.textSecond),
                  const SizedBox(height: 4),
                  Text(_modes[i].label,
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.textSecond,
                      )),
                ]),
              ),
            ),
          );
        }),
      ),
    ).animate().fadeIn();
  }

  // ── File drop zone ────────────────────────────────────────────────────────

  Widget _buildFilePicker() {
    final hasFile = _file != null;
    return Column(children: [
      DragTarget<String>(
        onWillAcceptWithDetails: (_) { setState(() => _isDragOver = true); return true; },
        onLeave: (_) => setState(() => _isDragOver = false),
        onAcceptWithDetails: (d) {
          setState(() => _isDragOver = false);
          final f = File(d.data);
          _validateFile(d.data, d.data.split(Platform.pathSeparator).last, f.lengthSync());
        },
        builder: (_, __, ___) => GestureDetector(
          onTap: _busy ? null : _pickFile,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 180,
            decoration: BoxDecoration(
              color: _isDragOver
                  ? AppColors.accentAmber.withOpacity(0.08)
                  : hasFile
                      ? AppColors.primary.withOpacity(0.06)
                      : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _isDragOver ? AppColors.accentAmber
                      : hasFile ? AppColors.primary : AppColors.border,
                  width: 1.5),
            ),
            child: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  _isDragOver ? Icons.file_download_rounded
                      : hasFile ? Icons.check_circle_rounded
                      : Icons.upload_file_rounded,
                  size: 48,
                  color: _isDragOver ? AppColors.accentAmber
                      : hasFile ? AppColors.accentGreen : AppColors.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  _isDragOver ? 'Drop it here!'
                      : hasFile ? _fileName!
                      : 'Tap to select · or drag & drop',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w600,
                      color: hasFile ? AppColors.accentGreen : AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text('PDF or DOCX · Max 10 MB', style: AppText.caption),
              ]),
            ),
          ),
        ),
      ),
      if (hasFile && !_busy) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() { _file = null; _fileName = null; }),
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Remove'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecond),
          ),
        ),
      ],
    ]);
  }

  // ── URL / YouTube field ───────────────────────────────────────────────────

  Widget _buildUrlField(String hint, String placeholder) {
    return TextField(
      controller: _urlCtrl,
      enabled: !_busy,
      style: TextStyle(color: AppColors.textPrimary),
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
        labelText: hint,
        labelStyle: TextStyle(color: AppColors.textSecond),
        filled: true,
        fillColor: AppColors.surface,
        prefixIcon: Icon(
          _mode == 1 ? Icons.play_circle_rounded : Icons.language_rounded,
          color: AppColors.primary, size: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
      onChanged: (_) => setState(() {}),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  // ── OCR camera picker ─────────────────────────────────────────────────────

  Widget _buildOcrPicker() {
    final hasImage = _file != null;
    return GestureDetector(
      onTap: _busy ? null : _pickImage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 180,
        decoration: BoxDecoration(
          color: hasImage ? AppColors.accentGreen.withOpacity(0.06) : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: hasImage ? AppColors.accentGreen : AppColors.border, width: 1.5),
        ),
        child: Center(
          child: hasImage
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_file!, height: 110, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 8),
                  Text('Image selected — tap to change',
                      style: AppText.caption),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.camera_alt_rounded,
                      size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text('Take a photo of handwritten notes',
                      style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('JPEG or PNG · Max 10 MB', style: AppText.caption),
                ]),
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildOfflineBanner() => AnimatedContainer(
    duration: const Duration(milliseconds: 350),
    height: _isOffline ? 44 : 0,
    color: AppColors.accentRed.withOpacity(0.92),
    child: _isOffline
        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('You\'re offline — uploads unavailable',
                style: AppText.label.copyWith(color: Colors.white)),
          ])
        : null,
  );

  Widget _buildErrorCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.accentRed.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.accentRed.withOpacity(0.3)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.warning_amber_rounded, color: AppColors.accentRed, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(_error!,
          style: AppText.caption.copyWith(color: AppColors.accentRed))),
    ]),
  );

  Widget _buildStepProgress() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(children: [
        if (_statusMsg.isNotEmpty) ...[
          Row(children: [
            if (_step < 4)
              SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                      color: _step == 3 ? AppColors.accentAmber : AppColors.primary))
            else
              const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(_statusMsg, style: AppText.bodySmall)),
          ]),
          const SizedBox(height: 20),
        ],
        Row(children: List.generate(_steps.length, (i) {
          final stepNum = i + 1;
          final isDone   = _step > stepNum;
          final isActive = _step == stepNum;
          final color = isDone ? AppColors.accentGreen
              : isActive ? AppColors.primary : AppColors.border;
          final bg = isDone ? AppColors.accentGreen.withOpacity(0.12)
              : isActive ? AppColors.primary.withOpacity(0.10) : AppColors.surface;
          return Expanded(
            child: Row(children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Column(children: [
                    Icon(isDone ? Icons.check_rounded : _steps[i].icon,
                        size: 16,
                        color: isDone ? AppColors.accentGreen
                            : isActive ? AppColors.primary : AppColors.textMuted),
                    const SizedBox(height: 4),
                    Text(_steps[i].label,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: isDone ? AppColors.accentGreen
                                : isActive ? AppColors.primary : AppColors.textMuted)),
                  ]),
                ),
              ),
              if (i < _steps.length - 1)
                AnimatedContainer(duration: const Duration(milliseconds: 400),
                    width: 8, height: 2,
                    color: _step > stepNum ? AppColors.accentGreen : AppColors.border),
            ]),
          );
        })),
      ]),
    ).animate().fadeIn();
  }

  Widget _buildCTA() {
    return GestureDetector(
      onTap: _canRun ? _run : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: _canRun ? AppColors.primaryGrad : null,
          color: _canRun ? null : AppColors.border,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_isOffline ? Icons.wifi_off_rounded : Icons.bolt_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            _isOffline ? 'No internet connection'
                : (_mode == 0 || _mode == 3) && _file == null ? 'Select a source first'
                : (_mode == 1 || _mode == 2) && _urlCtrl.text.trim().isEmpty ? 'Paste a URL first'
                : 'Generate Study Materials',
            style: AppText.body.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }

  Widget _buildTips() {
    final tips = [
      if (_mode == 0) ('📄', 'Text-based PDFs work best — not scanned images'),
      if (_mode == 1) ('🎬', 'Video must have captions (auto-generated is fine)'),
      if (_mode == 2) ('🌐', 'Wikipedia articles and blog posts work great'),
      if (_mode == 3) ('📸', 'Use good lighting and hold the camera steady'),
      ('⚡', 'Only the first ~3 000 characters are processed'),
      ('🤖', 'AI generation takes 30–90 seconds on first run'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TIPS', style: AppText.label),
        const SizedBox(height: 12),
        for (final t in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.$1, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Expanded(child: Text(t.$2, style: AppText.caption)),
            ]),
          ),
      ]),
    );
  }
}