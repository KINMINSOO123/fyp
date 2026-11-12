import 'package:flutter/material.dart';

import 'bakery_theme.dart';

class BakerySectionHeader extends StatelessWidget {
  const BakerySectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: BakeryColors.primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );
}

enum BakeryNoticeKind { info, warning, error }

class BakeryNotice extends StatelessWidget {
  const BakeryNotice(
    this.message, {
    this.kind = BakeryNoticeKind.info,
    super.key,
  });
  final String message;
  final BakeryNoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground, icon) = switch (kind) {
      BakeryNoticeKind.info => (
        const Color(0xFFE3F2FD),
        const Color(0xFF90CAF9),
        const Color(0xFF1565C0),
        Icons.info_outline,
      ),
      BakeryNoticeKind.warning => (
        const Color(0xFFFFF3E0),
        const Color(0xFFFFCC80),
        BakeryColors.warning,
        Icons.warning_amber,
      ),
      BakeryNoticeKind.error => (
        const Color(0xFFFFEBEE),
        const Color(0xFFEF9A9A),
        BakeryColors.error,
        Icons.error_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: foreground, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BakeryActionCard extends StatelessWidget {
  const BakeryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEFEBE9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: BakeryColors.primary, size: 22),
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(
            Icons.chevron_right,
            color: BakeryColors.primaryLight,
          ),
        ),
      ),
    ),
  );
}

class BakeryQuickAction extends StatelessWidget {
  const BakeryQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: BakeryColors.primary, size: 23),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
