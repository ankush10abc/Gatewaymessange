import 'package:flutter/material.dart';
import '../../constants/app_dimensions.dart';

class AppText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  const AppText.heading(
    this.text, {
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : style = const TextStyle(
          fontSize: AppDimensions.fontXXL,
          fontWeight: FontWeight.bold,
        );

  const AppText.title(
    this.text, {
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : style = const TextStyle(
          fontSize: AppDimensions.fontL,
          fontWeight: FontWeight.w600,
        );

  const AppText.body(
    this.text, {
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : style = const TextStyle(fontSize: AppDimensions.fontM);

  const AppText.caption(
    this.text, {
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : style = const TextStyle(
          fontSize: AppDimensions.fontS,
          color: Colors.grey,
        );

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
