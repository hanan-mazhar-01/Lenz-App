import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/lenz_colors.dart';
import '../../core/theme/lenz_motion.dart';
import '../../core/theme/lenz_text.dart';
import 'lenz_icons.dart';

/// The prototype's `.field`: 58px, radius 20, paper, 1.5px hairline border,
/// leading icon, 16/800 input. Focus turns the border forest2 and adds a 5px
/// `rgba(46,164,79,.16)` ring. Pass `obscure: true` for a password field with
/// an eye toggle; pass [errorText] for the error state.
class LenzField extends StatefulWidget {
  const LenzField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onFocusChanged,
    this.onTap,
    this.errorText,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.autofillHints,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLength,
    this.suffix,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;

  /// Name of a [LenzIcon] shown at the start.
  final String? icon;

  /// Password mode: hides the text and shows the eye toggle.
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Called when the field gains / loses focus (e.g. to close Lenz's eyes
  /// while a password is typed).
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onTap;

  /// Shows the error border and message when non-null / non-empty.
  final String? errorText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLength;

  /// Extra trailing widget (hidden when [obscure] shows the eye toggle).
  final Widget? suffix;
  final String? semanticLabel;

  @override
  State<LenzField> createState() => _LenzFieldState();
}

class _LenzFieldState extends State<LenzField> {
  FocusNode? _ownNode;
  bool _focused = false;
  late bool _hidden = widget.obscure;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(LenzField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
    if (old.obscure != widget.obscure) _hidden = widget.obscure;
  }

  void _onFocus() {
    if (_focused == _node.hasFocus) return;
    setState(() => _focused = _node.hasFocus);
    widget.onFocusChanged?.call(_focused);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final borderColor = hasError
        ? LenzColors.bad
        : _focused
            ? LenzColors.forest2
            : LenzColors.line;
    final List<BoxShadow> shadows = _focused
        ? [
            BoxShadow(
              color: hasError
                  ? LenzColors.bad.withValues(alpha: .14)
                  : LenzColors.focusRing,
              spreadRadius: 5,
            ),
          ]
        : LenzShadows.sh1;

    final showEye = widget.obscure;
    final trailing = showEye
        ? Semantics(
            button: true,
            label: _hidden ? 'Show password' : 'Hide password',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _hidden = !_hidden),
              child: SizedBox(
                width: 44,
                height: 58,
                child: Center(
                  child: LenzIcon(
                    _hidden ? LenzIcons.eye : LenzIcons.eyeOff,
                    size: 22,
                    color: LenzColors.subtle,
                  ),
                ),
              ),
            ),
          )
        : widget.suffix;

    final field = AnimatedContainer(
      duration: LenzMotion.field,
      curve: Curves.ease,
      height: 58,
      padding: EdgeInsets.only(left: 16, right: trailing != null ? 5 : 16),
      decoration: BoxDecoration(
        color: LenzColors.paper,
        borderRadius: BorderRadius.circular(LenzRadii.field),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: shadows,
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            LenzIcon(widget.icon!, size: 22, color: LenzColors.subtle),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Semantics(
              label: widget.semanticLabel,
              child: TextField(
                controller: widget.controller,
                focusNode: _node,
                enabled: widget.enabled,
                readOnly: widget.readOnly,
                autofocus: widget.autofocus,
                obscureText: showEye && _hidden,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                onTap: widget.onTap,
                autofillHints: widget.autofillHints,
                inputFormatters: widget.inputFormatters,
                textCapitalization: widget.textCapitalization,
                autocorrect: widget.autocorrect && !showEye,
                enableSuggestions: widget.enableSuggestions && !showEye,
                maxLength: widget.maxLength,
                maxLines: 1,
                style: LenzText.field,
                cursorColor: LenzColors.forest2,
                cursorWidth: 2,
                cursorRadius: const Radius.circular(2),
                // Explicit "no chrome": the app theme's InputDecorationTheme
                // would otherwise add its own outline inside our field.
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: LenzText.placeholder,
                  counterText: '',
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        AnimatedSize(
          duration: LenzMotion.field,
          curve: LenzMotion.ease,
          alignment: Alignment.topLeft,
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Text(
                    widget.errorText!,
                    style: LenzText.cap.copyWith(color: LenzColors.bad),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
