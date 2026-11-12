import 'package:flutter/widgets.dart';

mixin TextControllers<T extends StatefulWidget> on State<T> {
  final _controllers = <TextEditingController>[];

  List<TextEditingController> get textControllers =>
      List.unmodifiable(_controllers);

  TextEditingController textController([String text = '']) {
    final controller = TextEditingController(text: text);
    _controllers.add(controller);
    return controller;
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
