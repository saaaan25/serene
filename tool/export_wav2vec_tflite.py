"""Export a Wav2Vec2-base state_dict with dynamic INT8 weights and float32 I/O.

Run in the environment containing the training/conversion dependencies.
TensorFlow must be 2.17.x; use an onnx2tf release compatible with that environment.
"""

import argparse
import inspect
import copy
import json
import os
from pathlib import Path
import tempfile

import numpy as np
import torch
import tensorflow as tf
from tensorflow.lite.python import schema_py_generated as schema
from transformers import AutoConfig, AutoModelForAudioClassification
import onnx2tf


TARGET_SAMPLES = 80000
NUM_CLASSES = 3


class LogitsOnly(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_audio):
        return self.model(input_values=input_audio).logits


def validate_and_predict(path, samples):
    content = path.read_bytes()
    flat_model = schema.Model.GetRootAsModel(content, 0)
    for index in range(flat_model.OperatorCodesLength()):
        op = flat_model.OperatorCodes(index)
        if op.BuiltinCode() == schema.BuiltinOperator.CUSTOM:
            raise RuntimeError(f"Operador personalizado no permitido: {op.CustomCode()!r}")

    # Disable automatic Flex delegation: validation must use built-in ops only.
    interpreter = tf.lite.Interpreter(
        model_content=content,
        experimental_op_resolver_type=tf.lite.experimental.OpResolverType.BUILTIN_WITHOUT_DEFAULT_DELEGATES,
        num_threads=2,
    )
    interpreter.allocate_tensors()
    inputs = interpreter.get_input_details()
    outputs = interpreter.get_output_details()
    if len(inputs) != 1 or len(outputs) != 1:
        raise RuntimeError("Se requiere exactamente una entrada y una salida")
    for detail, shape in [(inputs[0], [1, TARGET_SAMPLES]), (outputs[0], [1, NUM_CLASSES])]:
        if detail['shape'].tolist() != shape or detail['dtype'] != np.float32:
            raise RuntimeError(f"Tensor incompatible con Flutter: {detail}")
    results = []
    for sample in samples:
        interpreter.set_tensor(inputs[0]['index'], sample.reshape(1, TARGET_SAMPLES))
        interpreter.invoke()
        output = interpreter.get_tensor(outputs[0]['index']).copy()
        if not np.isfinite(output).all():
            raise RuntimeError("El modelo produjo valores no finitos")
        results.append(output)
    return np.concatenate(results)


def predict_torch(model, samples):
    with torch.no_grad():
        predictions = np.concatenate([
            model(torch.from_numpy(x.reshape(1, TARGET_SAMPLES))).numpy()
            for x in samples
        ])
    if not np.isfinite(predictions).all():
        raise RuntimeError('PyTorch produjo valores no finitos')
    return predictions


def compare_predictions(reference, predictions):
    return {
        'synthetic_prediction_agreement': float(np.mean(predictions.argmax(axis=1) == reference.argmax(axis=1))),
        'synthetic_logit_mae': float(np.mean(np.abs(reference - predictions))),
        'accuracy': None,
        'note': 'Synthetic execution checks only; accuracy requires real labeled audio.',
    }


def inspect_quantization(path):
    content = path.read_bytes()
    model = schema.Model.GetRootAsModel(content, 0)
    names = {v: k for k, v in vars(schema.BuiltinOperator).items() if isinstance(v, int)}
    storage = {'int8': 0, 'float32': 0}
    operations = {}
    int8_weight_compute = 0
    seen_buffers = set()
    for gi in range(model.SubgraphsLength()):
        graph = model.Subgraphs(gi)
        for ti in range(graph.TensorsLength()):
            tensor = graph.Tensors(ti)
            buffer_id = tensor.Buffer()
            size = 0 if buffer_id in seen_buffers else model.Buffers(buffer_id).DataLength()
            seen_buffers.add(buffer_id)
            if tensor.Type() == schema.TensorType.INT8:
                storage['int8'] += size
            elif tensor.Type() == schema.TensorType.FLOAT32:
                storage['float32'] += size
        for oi in range(graph.OperatorsLength()):
            op = graph.Operators(oi)
            code = model.OperatorCodes(op.OpcodeIndex()).BuiltinCode()
            input_ids = [op.Inputs(i) for i in range(op.InputsLength()) if op.Inputs(i) >= 0]
            is_int8 = bool(input_ids) and graph.Tensors(input_ids[0]).Type() == schema.TensorType.INT8
            name = names.get(code, str(code)) + (' [int8 input]' if is_int8 else ' [other input]')
            operations[name] = operations.get(name, 0) + 1
            if code in (schema.BuiltinOperator.CONV_2D, schema.BuiltinOperator.DEPTHWISE_CONV_2D,
                        schema.BuiltinOperator.FULLY_CONNECTED, schema.BuiltinOperator.BATCH_MATMUL):
                if len(input_ids) >= 2 and graph.Tensors(input_ids[1]).Type() == schema.TensorType.INT8:
                    int8_weight_compute += 1
    if storage['int8'] == 0 or int8_weight_compute == 0:
        raise RuntimeError('No se encontraron pesos y operaciones de computo INT8; no se publicara el modelo')
    return {'constant_bytes': storage, 'compute_operations_with_int8_weights': int8_weight_compute,
            'operations_by_first_input_type': operations}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('weights', type=Path, help='Checkpoint .pt (state_dict) de Wav2Vec2-base, 3 clases')
    args = parser.parse_args()
    # Architecture, shapes and destination are fixed; only the checkpoint is input.
    args.output = Path('model.tflite')
    if not tf.__version__.startswith('2.17.'):
        raise RuntimeError(f'Usa TensorFlow 2.17.x; actual: {tf.__version__}')
    if not args.weights.is_file():
        raise FileNotFoundError(args.weights)
    torch.manual_seed(42)
    rng = np.random.default_rng(42)
    time = np.arange(TARGET_SAMPLES, dtype=np.float32) / 16000
    samples = np.stack([
        np.zeros(TARGET_SAMPLES, np.float32),
        rng.uniform(-0.1, 0.1, TARGET_SAMPLES).astype(np.float32),
        (0.1 * np.sin(2 * np.pi * 440 * time)).astype(np.float32),
    ])
    print('Sin audio real: cuantizacion dinamica de pesos INT8, sin calibracion de activaciones.')
    print('Las entradas sinteticas solo comprueban ejecucion; no miden precision real.')

    print('1. Cargando pesos sin permitir claves faltantes o inesperadas...')
    config = AutoConfig.from_pretrained('facebook/wav2vec2-base', num_labels=NUM_CLASSES)
    model = AutoModelForAudioClassification.from_config(config, attn_implementation='eager')
    state_dict = torch.load(args.weights, map_location='cpu', weights_only=True)
    model.load_state_dict(state_dict, strict=True)
    model.eval()
    # Reference keeps the training configuration and its original activations.
    original = predict_torch(LogitsOnly(model).eval(), samples)
    export_config = copy.deepcopy(config)
    export_config.feat_extract_activation = 'gelu_fast'
    export_config.hidden_act = 'gelu_fast'
    export_model = AutoModelForAudioClassification.from_config(export_config, attn_implementation='eager')
    export_model.load_state_dict(state_dict, strict=True)
    wrapper = LogitsOnly(export_model).eval()
    reference = predict_torch(wrapper, samples)
    del model, export_model, state_dict

    # Only this script's temporary directory is cleaned up, even on failure.
    with tempfile.TemporaryDirectory(prefix='serene_export_') as directory:
        work = Path(directory)
        onnx_path = work / 'wav2vec.onnx'
        output_dir = work / 'tf_model_out'
        print('2. Exportando ONNX con entrada fija y salida logits...')
        options = dict(export_params=True, opset_version=14, do_constant_folding=True,
                       input_names=['input_audio'], output_names=['logits'], dynamic_axes=None)
        if 'dynamo' in inspect.signature(torch.onnx.export).parameters:
            options['dynamo'] = False
        torch.onnx.export(wrapper, torch.from_numpy(samples[:1].copy()), str(onnx_path), **options)
        print('3. Generando SavedModel y referencia float32...')
        onnx2tf.convert(input_onnx_file_path=str(onnx_path),
                        output_folder_path=str(output_dir), output_signaturedefs=True,
                        output_integer_quantized_tflite=False,
                        keep_shape_absolutely_input_names=['input_audio'], non_verbose=True)
        candidates = sorted(output_dir.glob('*_float32.tflite'))
        if len(candidates) != 1:
            raise RuntimeError(f"Se esperaba un solo *_float32.tflite; encontrados: {candidates}")
        float_candidate = candidates[0]
        float_predictions = validate_and_predict(float_candidate, samples)
        np.testing.assert_allclose(float_predictions, reference, atol=1e-3, rtol=1e-3)
        if not (output_dir / 'saved_model.pb').is_file():
            raise RuntimeError('onnx2tf no produjo el SavedModel esperado')

        print('4. Cuantizando pesos INT8 por rango dinamico; entrada/salida float32...')
        converter = tf.lite.TFLiteConverter.from_saved_model(str(output_dir))
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
        converter.inference_input_type = tf.float32
        converter.inference_output_type = tf.float32
        converter.allow_custom_ops = False
        candidate = work / 'model_int8_float_io.tflite'
        candidate.write_bytes(converter.convert())

        print('5. Validando pesos INT8, runtime 2.17 y ejecucion sintetica...')
        quantization = inspect_quantization(candidate)
        predictions = validate_and_predict(candidate, samples)
        report = {
            'tensorflow': tf.__version__,
            'quantization_mode': 'dynamic_range',
            'calibration_windows': 0,
            'synthetic_test_windows': len(samples),
            'float32_bytes': float_candidate.stat().st_size,
            'quantized_bytes': candidate.stat().st_size,
            'quantization': quantization,
            'float32_vs_original': compare_predictions(original, float_predictions),
            'int8_vs_float32': compare_predictions(float_predictions, predictions),
            'int8_vs_original': compare_predictions(original, predictions),
            'assumed_original_config': 'facebook/wav2vec2-base',
            'export_activation': 'gelu_fast',
            'class_order': ['no_violence', 'physical_violence', 'verbal_violence'],
            'real_accuracy_validated': False,
        }
        report['size_reduction'] = 1 - report['quantized_bytes'] / report['float32_bytes']
        report['accepted'] = report['size_reduction'] > 0
        report_path = args.output.with_suffix('.report.json')
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report, indent=2))
        if not report['accepted']:
            raise RuntimeError(f'Validacion rechazada; modelo destino intacto. Revisa {report_path}')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Publish atomically after all checks; existing model survives failures.
        with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False, suffix='.tmp') as output:
            temporary_output = Path(output.name)
            output.write(candidate.read_bytes())
        try:
            os.replace(temporary_output, args.output)
        finally:
            temporary_output.unlink(missing_ok=True)
        print(f'Completado: {args.output.resolve()} ({args.output.stat().st_size / 1024**2:.1f} MiB)')
        print('Confirma que el orden de clases coincide con assets/labels/labels.txt.')


if __name__ == '__main__':
    main()
