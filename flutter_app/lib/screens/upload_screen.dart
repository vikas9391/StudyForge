// lib/screens/upload_screen.dart
// File upload screen with animated drop zone, step progress, and gradient CTA.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../main.dart' show slideRoute;
import 'results_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _api  = ApiService();
  final _auth = AuthService();

  File?   _file;
  String? _fileName;
  double  _fileSizeMb = 0;

  bool    _uploading  = false;
  bool    _processing = false;
  String  _statusMsg  = '';
  String? _error;

  // Step: 0 = idle, 1 = uploading, 2 = processing
  int _step = 0;

  bool get _busy => _uploading || _processing;

  // ── Pick file ──────────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type:               FileType.custom,
      allowedExtensions:  ['pdf', 'doc', 'docx'],
      withData:           false,
      withReadStream:     false,
    );

    if (result == null || result.files.isEmpty) return;

    final picked   = result.files.single;
    final sizeMb   = picked.size / (1024 * 1024);

    if (sizeMb > 10) {
      setState(() => _error = 'File is ${sizeMb.toStringAsFixed(1)} MB — max is 10 MB.');
      return;
    }

    setState(() {
      _file       = File(picked.path!);
      _fileName   = picked.name;
      _fileSizeMb = sizeMb;
      _error      = null;
    });
  }

  // ── Upload → Process ───────────────────────────────────────────────────────
  Future<void> _run() async {
    if (_file == null) return;
    final uid = _auth.userId;
    if (uid == null) {
      setState(() => _error = 'You must be signed in.');
      return;
    }

    setState(() {
      _uploading  = true;
      _step       = 1;
      _error      = null;
      _statusMsg  = 'Uploading file…';
    });

    try {
      // Step 1 — upload to backend
      final uploadData = await _api.uploadFile(file: _file!, userId: uid);

      final resultId     = uploadData['result_id']      as String;
      final extractedText = uploadData['extracted_text'] as String;

      setState(() {
        _uploading  = false;
        _processing = true;
        _step       = 2;
        _statusMsg  = 'AI is generating your study materials… (30–60 s)';
      });

      // Step 2 — AI processing
      final studyResult = await _api.processDocument(
        resultId:      resultId,
        extractedText: extractedText,
        userId:        uid,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          slideRoute(ResultsScreen(resultId: studyResult.resultId)));

    } catch (e) {
      setState(() {
        _error      = e.toString();
        _uploading  = false;
        _processing = false;
        _step       = 0;
        _statusMsg  = '';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.textSecond),
        title:   Text('Upload Document', style: AppText.subheading),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGrad),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              _buildDropZone(),

              if (_file != null) ...[
                const SizedBox(height: 12),
                _buildFileInfo(),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                _buildErrorCard(),
              ],

              if (_busy) ...[
                const SizedBox(height: 16),
                _buildProgressCard(),
              ],

              const SizedBox(height: 20),

              // Main CTA button
              GestureDetector(
                onTap: _busy || _file == null ? null : _run,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: (_busy || _file == null)
                        ? null
                        : AppColors.primaryGrad,
                    color: (_busy || _file == null)
                        ? AppColors.border
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: (_busy || _file == null)
                        ? []
                        : [
                            BoxShadow(
                              color:      AppColors.primaryGlow,
                              blurRadius: 18,
                              offset:     const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _file == null
                            ? 'Select a file first'
                            : 'Generate Study Materials',
                        style: AppText.body.copyWith(
                          color:      Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              _buildTips(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Drop zone ──────────────────────────────────────────────────────────────
  Widget _buildDropZone() {
    return GestureDetector(
      onTap: _busy ? null : _pickFile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 180,
        decoration: BoxDecoration(
          color: _file != null
              ? AppColors.primary.withOpacity(0.06)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _file != null ? AppColors.primary : AppColors.border,
            width: _file != null ? 2 : 1,
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              key:   ValueKey(_file != null),
              _file != null
                  ? Icons.check_circle_rounded
                  : Icons.upload_file_rounded,
              size:  52,
              color: _file != null
                  ? AppColors.accentGreen
                  : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _file != null ? 'File selected!' : 'Tap to select a file',
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text('PDF or DOCX  ·  Max 10 MB', style: AppText.caption),
        ]),
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.96, 0.96));
  }

  // ── File info card ─────────────────────────────────────────────────────────
  Widget _buildFileInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Row(children: [
        Container(
          width:  40,
          height: 40,
          decoration: BoxDecoration(
            color:        AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.insert_drive_file_rounded,
              color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _fileName ?? '',
              style:    AppText.bodySmall.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_fileSizeMb.toStringAsFixed(1)} MB',
              style: AppText.caption,
            ),
          ]),
        ),
        if (!_busy)
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 18),
            onPressed: () => setState(() {
              _file     = null;
              _fileName = null;
            }),
          ),
      ]),
    ).animate().fadeIn().slideY(begin: 0.15);
  }

  // ── Error card ─────────────────────────────────────────────────────────────
  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppColors.accentRed.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded,
            color: AppColors.accentRed, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _error!,
            style: AppText.caption.copyWith(color: AppColors.accentRed),
          ),
        ),
      ]),
    );
  }

  // ── Progress card ──────────────────────────────────────────────────────────
  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(children: [
        // Status row
        Row(children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color:       _processing
                  ? AppColors.accentAmber
                  : AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(_statusMsg, style: AppText.bodySmall)),
        ]),

        const SizedBox(height: 18),

        // Step dots
        Row(children: [
          _StepDot(done: _step > 1, active: _step == 1),
          _StepLine(filled: _step > 1),
          _StepDot(done: false, active: _step == 2),
          _StepLine(filled: false),
          _StepDot(done: false, active: false),
        ]),

        const SizedBox(height: 7),

        // Step labels
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Upload',
              style: AppText.label.copyWith(
                  color: _step >= 1 ? AppColors.accentGreen : AppColors.textMuted)),
          Text('AI Analysis',
              style: AppText.label.copyWith(
                  color: _step == 2 ? AppColors.accentAmber : AppColors.textMuted)),
          Text('Results',
              style: AppText.label.copyWith(color: AppColors.textMuted)),
        ]),
      ]),
    ).animate().fadeIn();
  }

  // ── Tips card ──────────────────────────────────────────────────────────────
  Widget _buildTips() {
    const tips = [
      ('📄', 'Text-based PDFs work best — not scanned images'),
      ('⚡', 'Only the first 20 pages are processed'),
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

// ── Step indicator widgets ────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final bool done;
  final bool active;
  const _StepDot({required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.accentGreen
        : active
            ? AppColors.primary
            : AppColors.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width:  14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: active
            ? [BoxShadow(color: AppColors.primaryGlow, blurRadius: 8)]
            : [],
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 9, color: Colors.white)
          : null,
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool filled;
  const _StepLine({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: 2,
        color: filled ? AppColors.accentGreen : AppColors.border,
      ),
    );
  }
}
