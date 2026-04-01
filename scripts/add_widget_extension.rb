#!/usr/bin/env ruby
# Adds the StudyWidget WidgetKit extension target to the Xcode project.
# Requires the 'xcodeproj' gem (pre-installed on Codemagic).

require 'xcodeproj'

PROJECT_PATH = File.join(__dir__, '..', 'ios', 'Runner.xcodeproj')
WIDGET_DIR = 'StudyWidget'
WIDGET_TARGET_NAME = 'StudyWidgetExtension'
WIDGET_BUNDLE_ID = 'com.niotron.domingotambasacan.pnleaireviewer2026.StudyWidget'
APP_GROUP = 'group.com.niotron.domingotambasacan.pnleaireviewer2026'
DEPLOYMENT_TARGET = '16.0'

project = Xcodeproj::Project.open(PROJECT_PATH)

# Skip if target already exists
if project.targets.any? { |t| t.name == WIDGET_TARGET_NAME }
  puts "#{WIDGET_TARGET_NAME} target already exists, skipping."
  exit 0
end

puts "Adding #{WIDGET_TARGET_NAME} target..."

# --- Add file references ---
widget_group = project.main_group.new_group(WIDGET_DIR, WIDGET_DIR)

swift_files = []
Dir.glob(File.join(PROJECT_PATH, '..', WIDGET_DIR, '*.swift')).each do |f|
  ref = widget_group.new_reference(File.basename(f))
  swift_files << ref
end

info_plist_ref = widget_group.new_reference('Info.plist')
entitlements_ref = widget_group.new_reference('StudyWidgetExtension.entitlements')

# --- Create the target ---
target = project.new_target(
  :app_extension,
  WIDGET_TARGET_NAME,
  :ios,
  DEPLOYMENT_TARGET
)

# --- Add source files to target ---
swift_files.each do |ref|
  target.source_build_phase.add_file_reference(ref)
end

# --- Add WidgetKit and SwiftUI frameworks ---
target.frameworks_build_phase.clear
['WidgetKit', 'SwiftUI'].each do |fw_name|
  fw_ref = project.frameworks_group.new_reference("System/Library/Frameworks/#{fw_name}.framework")
  fw_ref.source_tree = 'SDKROOT'
  target.frameworks_build_phase.add_file_reference(fw_ref)
end

# --- Configure build settings ---
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE_ID
  config.build_settings['INFOPLIST_FILE'] = "#{WIDGET_DIR}/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{WIDGET_DIR}/StudyWidgetExtension.entitlements"
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  config.build_settings['MARKETING_VERSION'] = '1.1.8'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '20'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  config.build_settings['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = 'WidgetBackground'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
end

# --- Add widget extension as dependency of Runner ---
runner_target = project.targets.find { |t| t.name == 'Runner' }
if runner_target
  runner_target.add_dependency(target)

  # Embed the extension in Runner
  embed_phase = runner_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.dst_subfolder_spec = '13' # PlugIns folder
  build_file = embed_phase.add_file_reference(target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  # Add App Group entitlement to Runner
  runner_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] ||= 'Runner/Runner.entitlements'
  end
end

project.save

puts "#{WIDGET_TARGET_NAME} added successfully!"
