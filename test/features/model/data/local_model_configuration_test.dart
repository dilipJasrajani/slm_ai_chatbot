import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/model/data/local_model_configuration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled Gemma configuration selects the local asset and model type',
    () {
      const model = LocalModelConfiguration.gemma3;

      expect(model.fileName, 'gemma3-1b-it.litertlm');
      expect(model.source, 'assets/models/gemma3-1b-it.litertlm');
      expect(model.source, endsWith(model.fileName));
      expect(model.modelType, ModelType.gemmaIt);
      expect(model.bundledAsset, isTrue);
      expect(model.usesQwen3Output, isFalse);
      expect(model.label, 'Gemma 3 1B · Local');
    },
  );

  test('Gemma model is declared as a Flutter asset', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

    expect(
      manifest.listAssets(),
      contains(LocalModelConfiguration.gemma3.source),
    );
  });

  test('Qwen3 configuration retains the existing network installation', () {
    const model = LocalModelConfiguration.qwen3;

    expect(model.fileName, 'Qwen3-0.6B.litertlm');
    expect(model.source, endsWith(model.fileName));
    expect(model.source, startsWith('https://huggingface.co/'));
    expect(model.modelType, ModelType.qwen3);
    expect(model.bundledAsset, isFalse);
    expect(model.usesQwen3Output, isTrue);
    expect(model.label, 'Qwen3 0.6B · Local');
  });
}
