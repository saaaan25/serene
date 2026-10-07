require 'json'
require 'pathname'
require 'uri'

package_config_path = Pathname.new('.dart_tool/package_config.json')
abort "No se encontró #{package_config_path}; ejecuta flutter pub get primero" unless package_config_path.file?

package_config = JSON.parse(package_config_path.read)
package = package_config.fetch('packages').find { |entry| entry['name'] == 'tflite_flutter' }
abort 'tflite_flutter no aparece en .dart_tool/package_config.json' unless package

package_root = URI.parse(package.fetch('rootUri'))
package_root_path =
  if package_root.scheme == 'file'
    Pathname.new(URI::DEFAULT_PARSER.unescape(package_root.path))
  else
    package_config_path.dirname.join(package_root.path)
  end

podspec = package_root_path.join('ios', 'tflite_flutter.podspec')
abort "No se encontró el podspec de tflite_flutter: #{podspec}" unless podspec.file?

contents = File.read(podspec)
replacement = "tflite_version = '2.17.0'"
pattern = /tflite_version\s*=\s*'[^']+'/
abort "No se encontro tflite_version en #{podspec}" unless contents.match?(pattern)
File.write(podspec, contents.sub(pattern, replacement))
puts "TensorFlow Lite iOS fijado a 2.17.0: #{podspec}"
