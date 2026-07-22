import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A clickable IP address. Tapping it opens the printer's built-in web page
/// (`http://<ip>`) in the technician's browser — handy from both the printer
/// list and the printer detail card.
class IpAddressLink extends StatelessWidget {
  const IpAddressLink(this.ip, {super.key, this.style, this.placeholder = '—'});

  final String? ip;
  final TextStyle? style;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final value = ip?.trim();
    if (value == null || value.isEmpty) return Text(placeholder, style: style);
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Open http://$value in browser',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _open(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new, size: 13, color: primary),
              const SizedBox(width: 4),
              Text(
                value,
                style: (style ?? const TextStyle()).copyWith(
                  color: primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: primary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String ip) async {
    final uri = Uri.parse('http://$ip');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text('Could not open $uri')));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }
}
