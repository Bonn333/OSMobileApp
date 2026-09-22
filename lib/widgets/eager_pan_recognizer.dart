import 'package:flutter/gestures.dart';

/// Claims the pointer as soon as it goes down.
///
/// Without this the modal sheet's drag-to-dismiss and the surrounding scroll
/// view win the gesture arena, so dragging a control closed the sheet or
/// scrolled the page instead of changing the value.
class EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
