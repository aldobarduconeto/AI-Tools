require 'json'

def prepare_lame_pod(platform)
  manifest = File.expand_path('../.flutter-plugins-dependencies', __dir__)
  return unless File.file?(manifest)

  plugin = JSON.parse(File.read(manifest)).dig('plugins', platform)
               &.find { |entry| entry['name'] == 'flutter_lame' }
  return unless plugin

  root = plugin.fetch('path')
  source = File.join(root, 'src', 'lame')
  classes = File.join(root, platform, 'Classes')
  return if File.directory?(classes)

  # CocoaPods skips prepare_command for Flutter's local plugin pods.
  raise 'Bundled LAME sources are missing' unless File.directory?(source)
  File.symlink('../src/lame', classes)
end
