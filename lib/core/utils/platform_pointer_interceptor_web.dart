import 'dart:html' as html;

void setMapPointerEvents(bool enabled) {
  try {
    final iframes = html.document.querySelectorAll('iframe');
    for (var element in iframes) {
      if (element is html.IFrameElement && (element.id ?? '').startsWith('google-map-editor-')) {
        element.style.pointerEvents = enabled ? 'auto' : 'none';
      }
    }
  } catch (_) {
    // Fail silently on errors
  }
}
