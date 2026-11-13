import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/bakery_widgets.dart';
import '../data/ai_suggestions_service.dart';
import 'ai_review_screen.dart';

class AiSuggestionsScreen extends StatefulWidget {
  const AiSuggestionsScreen({this.gateway, super.key});
  final AiSuggestionsGateway? gateway;

  @override
  State<AiSuggestionsScreen> createState() => _AiSuggestionsScreenState();
}

class _AiSuggestionsScreenState extends State<AiSuggestionsScreen> {
  late final AiSuggestionsGateway _gateway;
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;
  List<AiBreadSuggestion>? _suggestions;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? AiSuggestionsService();
  }

  @override
  void dispose() {
    _description.dispose();
    if (widget.gateway == null) (_gateway as AiSuggestionsService).close();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_busy) return;
    final description = _description.text.trim();
    if (description.length < 10 || description.length > 500) {
      setState(() => _error = 'Describe the bread in 10 to 500 characters.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _suggestions = null;
    });
    try {
      final suggestions = await _gateway.generate(description);
      if (mounted) setState(() => _suggestions = suggestions);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to generate suggestions. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(AiBreadSuggestion suggestion) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AiReviewScreen(draft: suggestion)),
    );
    if (created == true && mounted) {
      final current = _suggestions;
      if (current != null) {
        setState(
          () => _suggestions = current
              .where((item) => !identical(item, suggestion))
              .toList(),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bread category and recipe added. Inventory will show the updated catalogue.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Bread Suggestions')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const BakeryNotice(
            'AI-generated recipes are drafts for review and trial baking. '
            'Nothing is added to the bread catalogue or inventory automatically.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            enabled: !_busy,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Describe the bread you want',
              hintText: 'Suggest a bun similar to Coconut Bun.',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _generate(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Generate suggestions'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Generating up to three draft recipes...'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            BakeryNotice(_error!, kind: BakeryNoticeKind.error),
          ],
          if (_suggestions != null) ...[
            const BakerySectionHeader('Draft suggestions'),
            for (final suggestion in _suggestions!)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(suggestion.description),
                        const SizedBox(height: 8),
                        Text('Why suggested: ${suggestion.reason}'),
                        const SizedBox(height: 12),
                        Text(
                          'Draft recipe · grams per bread',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        for (final ingredient in suggestion.recipe)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${ingredient.name}: '
                                  '${ingredient.gramsPerBread} g',
                                ),
                                if (ingredient.availability ==
                                    'NOT_IN_INVENTORY')
                                  Text(
                                    'Not in existing inventory',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                if (ingredient.availability == 'OUT_OF_STOCK')
                                  Text(
                                    'Listed ingredient, no valid stock available',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _review(suggestion),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Review & Add'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
