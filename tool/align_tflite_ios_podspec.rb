podspec = 'ios/.symlinks/plugins/tflite_flutter/ios/tflite_flutter.podspec'
contents = File.read(podspec)
original = "tflite_version = '2.12.0'"
replacement = "tflite_version = '0.0.1-nightly.20230414'"

if contents.include?(original)
  File.write(podspec, contents.sub(original, replacement))
elsif !contents.include?(replacement)
  abort "No se encontró la versión esperada en #{podspec}"
end
