import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/model_management/data/model_management_service.dart';
import 'package:fyp/features/model_management/domain/model_review.dart';
import 'package:fyp/features/model_management/presentation/model_detail_screen.dart';
import 'package:fyp/features/model_management/presentation/model_list_screen.dart';

const categoryId = '00000000-0000-4000-8000-000000000001';
const groupId = '00000000-0000-4000-8000-000000000002';
const fingerprint = 'same-test-fingerprint';

Map<String, dynamic> evaluationJson(
  String id,
  double mae, {
  String holdout = fingerprint,
}) => {
  'id': id,
  'holdoutStart': '2026-10-29',
  'holdoutEnd': '2026-11-03',
  'holdoutFingerprint': holdout,
  'evaluationLabel': 'SIMULATION_BASED',
  'dataOrigins': ['SIMULATION_GENERATED'],
  'mae': mae,
  'rmse': mae + 1,
  'mape': null,
  'rSquared': -0.2,
  'sampleCount': 6,
  'mapeSampleCount': 0,
};

ModelVersionReview model(
  String id,
  String type,
  String status, {
  double? mae,
  String holdout = fingerprint,
}) => ModelVersionReview.fromJson({
  'id': id,
  'version': id == 'candidate' ? 2 : 1,
  'breadCategoryId': categoryId,
  'breadCategoryName': 'Wholemeal Bread',
  'modelType': type,
  'lifecycleStatus': status,
  'trainingStart': '2026-10-05',
  'trainingEnd': '2026-10-28',
  'holdoutStart': '2026-10-29',
  'trainingGroupId': id == 'active' ? 'older-group' : groupId,
  'trainingOriginCounts': {'SIMULATION_GENERATED': 24},
  'holdoutOriginCounts': {'SIMULATION_GENERATED': 6},
  'latestEvaluation': mae == null
      ? null
      : evaluationJson('$id-eval', mae, holdout: holdout),
});

class FakeModelGateway implements ModelManagementGateway {
  FakeModelGateway(this.versions);
  List<ModelVersionReview> versions;
  int trainCalls = 0;
  int evaluationCalls = 0;
  int activationCalls = 0;

  @override
  Future<List<TrainingCategory>> listCategories() async => [
    const TrainingCategory(
      id: categoryId,
      name: 'Wholemeal Bread',
      displayOrder: 1,
    ),
  ];
  @override
  Future<ModelReviewPage> listModels({
    String? breadCategoryId,
    int page = 1,
  }) async => ModelReviewPage(
    items: versions,
    page: page,
    pageSize: 20,
    total: versions.length,
  );
  @override
  Future<ModelVersionReview> getModel(String id) async =>
      versions.firstWhere((version) => version.id == id);
  @override
  Future<void> train(String breadCategoryId) async {
    trainCalls++;
  }

  @override
  Future<void> evaluate(String modelId) async {
    evaluationCalls++;
  }

  @override
  Future<void> activate(String modelId, String evaluationId) async {
    activationCalls++;
  }

  @override
  Future<void> restore(String modelId) async {}
}

void main() {
  test(
    'T-DP-UI-01 [FR-DP-11, NFR-ACC-05]: null metrics and negative R² stay honest',
    () {
      final review = ModelEvaluationReview.fromJson(evaluationJson('eval', 2));
      expect(review.mape, isNull);
      expect(review.rSquared, -0.2);
    },
  );

  testWidgets('T-DP-UI-02 [FR-DP-06]: admin selects category before training', (
    tester,
  ) async {
    final fake = FakeModelGateway([]);
    await tester.pumpWidget(MaterialApp(home: ModelListScreen(gateway: fake)));
    await tester.pumpAndSettle();
    expect(find.text('Train Candidates'), findsOneWidget);
    await tester.tap(find.text('Train Candidates'));
    expect(fake.trainCalls, 0);
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wholemeal Bread').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Train Candidates'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not activate'), findsOneWidget);
    await tester.tap(find.text('Train').last);
    await tester.pumpAndSettle();
    expect(fake.trainCalls, 1);
  });

  testWidgets(
    'T-DP-UI-03 [FR-DP-12, NFR-ACC-05]: higher-MAE candidate cannot activate',
    (tester) async {
      final fake = FakeModelGateway([
        model('candidate', 'RANDOM_FOREST', 'CANDIDATE', mae: 4),
        model('baseline', 'LINEAR_REGRESSION', 'CANDIDATE', mae: 5),
        model('active', 'RANDOM_FOREST', 'ACTIVE', mae: 3),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: ModelDetailScreen(modelId: 'candidate', gateway: fake),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Activate Candidate'), 250);
      expect(find.textContaining('same test set'), findsWidgets);
      await tester.tap(find.text('Activate Candidate'));
      expect(fake.activationCalls, 0);
    },
  );

  testWidgets(
    'T-DP-UI-04 [FR-DP-12]: first activation requires explicit confirmation',
    (tester) async {
      final fake = FakeModelGateway([
        model('candidate', 'RANDOM_FOREST', 'CANDIDATE', mae: 2),
        model('baseline', 'LINEAR_REGRESSION', 'CANDIDATE', mae: 3),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: ModelDetailScreen(modelId: 'candidate', gateway: fake),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.activationCalls, 0);
      await tester.scrollUntilVisible(find.text('Activate Candidate'), 250);
      await tester.tap(find.text('Activate Candidate'));
      await tester.pumpAndSettle();
      expect(find.text('Activate candidate?'), findsOneWidget);
      expect(fake.activationCalls, 0);
      await tester.tap(find.text('Activate').last);
      await tester.pumpAndSettle();
      expect(fake.activationCalls, 1);
    },
  );
}
